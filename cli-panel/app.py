#!/usr/bin/env python3
"""sip.polytronx.com — Outbound CLI panel.

A tiny authenticated web panel that:
  * shows the current outbound caller ID (CLI) and trunk health,
  * changes the CLI in the live Asterisk config (etc/extensions.conf + .env)
    and reloads the dialplan,
  * fires test calls through the outbound trunk,
  * keeps timestamped backups and a change history.

Talks to Asterisk by exec'ing into the sip-asterisk container over the Docker
socket (Docker Engine API). Python stdlib only — no pip dependencies.

Config files are edited IN PLACE (no rename) because .env is a single-file
bind mount; renaming would break the mount.
"""

import hmac
import http.client
import json
import os
import re
import secrets
import socket
import threading
import time
from collections import defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

APP_DIR = os.path.dirname(os.path.abspath(__file__))
INDEX_FILE = os.path.join(APP_DIR, "index.html")

DATA_DIR = os.environ.get("PANEL_DATA", "/data/panel-data")
ETC_DIR = "/data/etc"
EXT_FILE = os.path.join(ETC_DIR, "extensions.conf")
ENV_FILE = "/data/env/.env"
BACKUP_DIR = os.path.join(DATA_DIR, "backups")
HIST_FILE = os.path.join(DATA_DIR, "history.jsonl")

AST_CONTAINER = os.environ.get("ASTERISK_CONTAINER", "sip-asterisk")
DOCKER_SOCK = os.environ.get("DOCKER_SOCK", "/var/run/docker.sock")
PANEL_USER = os.environ.get("PANEL_USER", "admin")
PANEL_PASSWORD = os.environ.get("PANEL_PASSWORD", "")
PORT = int(os.environ.get("PANEL_PORT", "8080"))

SESSION_TTL = 12 * 3600
COOKIE_NAME = "panel_session"
MAX_BODY = 4096

BACKUPS_TO_KEEP = 20
HISTORY_TO_SHOW = 15

# same => n,Set(OUTCLI=92519206648)
EXT_CLI_LINE = re.compile(
    r"(?m)^(?P<prefix>\s*same => n,Set\(OUTCLI=)(?P<val>\+?[0-9]+)(?P<suffix>\)\s*)$"
)
# OUTBOUND_CLI=92519206648
ENV_CLI_LINE = re.compile(r"(?m)^(?P<prefix>OUTBOUND_CLI=)(?P<val>\+?[0-9]+)\s*$")

_lock = threading.Lock()          # serializes config edits
_sessions = {}                    # token -> expiry (in-memory; restart logs you out)
_rate = defaultdict(deque)        # ip -> deque[timestamps] for /api/*
_login_rate = defaultdict(deque)  # ip -> deque[timestamps] for /api/login


# --------------------------------------------------------------------------- docker

class _UnixHTTP(http.client.HTTPConnection):
    def __init__(self, sock_path):
        super().__init__("localhost")
        self._sock_path = sock_path

    def connect(self):
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(45)
        s.connect(self._sock_path)
        self.sock = s


def docker_exec(argv):
    """Run a command inside the Asterisk container, return (exit_code, output)."""
    body = json.dumps({"Cmd": list(argv), "AttachStdout": True,
                       "AttachStderr": True, "Tty": True})
    conn = _UnixHTTP(DOCKER_SOCK)
    conn.request("POST", f"/v1.43/containers/{AST_CONTAINER}/exec", body,
                 {"Content-Type": "application/json"})
    r = conn.getresponse()
    payload = r.read()
    if r.status // 100 != 2:
        raise RuntimeError(f"docker exec create failed: HTTP {r.status} {payload[:300]!r}")
    exec_id = json.loads(payload)["Id"]

    conn = _UnixHTTP(DOCKER_SOCK)
    conn.request("POST", f"/v1.43/exec/{exec_id}/start",
                 json.dumps({"Detach": False, "Tty": True}),
                 {"Content-Type": "application/json"})
    r = conn.getresponse()
    out = r.read()
    if r.status // 100 != 2:
        raise RuntimeError(f"docker exec start failed: HTTP {r.status} {out[:300]!r}")

    conn = _UnixHTTP(DOCKER_SOCK)
    conn.request("GET", f"/v1.43/exec/{exec_id}/json")
    r = conn.getresponse()
    exit_code = json.loads(r.read()).get("ExitCode", -1) if r.status == 200 else -1
    return exit_code, out.decode("utf-8", "replace").strip()


def asterisk_cli(command):
    code, out = docker_exec(["asterisk", "-rx", command])
    if code != 0:
        raise RuntimeError(f"asterisk -rx {command!r} exited {code}: {out[:400]}")
    return out


# --------------------------------------------------------------------------- config

def _read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def _write_inplace(path, text):
    # Same inode: .env is a single-file bind mount, rename would detach it.
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
        f.flush()
        os.fsync(f.fileno())


def _backup(path):
    os.makedirs(BACKUP_DIR, exist_ok=True)
    ts = time.strftime("%Y%m%d-%H%M%S")
    dst = os.path.join(BACKUP_DIR, f"{os.path.basename(path)}.{ts}.bak")
    with open(dst, "w", encoding="utf-8") as out:
        out.write(_read(path))
    # rotate
    prefix = os.path.basename(path) + "."
    olds = sorted(f for f in os.listdir(BACKUP_DIR) if f.startswith(prefix))
    for f in olds[:-BACKUPS_TO_KEEP] if len(olds) > BACKUPS_TO_KEEP else []:
        os.unlink(os.path.join(BACKUP_DIR, f))


def _history_add(entry):
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(HIST_FILE, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry) + "\n")


def _history_list(limit=HISTORY_TO_SHOW):
    try:
        with open(HIST_FILE, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except FileNotFoundError:
        return []
    out = []
    for line in lines[-limit:]:
        try:
            out.append(json.loads(line))
        except ValueError:
            continue
    return list(reversed(out))


def current_cli():
    m = EXT_CLI_LINE.search(_read(EXT_FILE))
    if not m:
        raise RuntimeError("OUTCLI line not found in extensions.conf — panel config mismatch")
    return m.group("val")


def _history_sync():
    """Record CLI values changed outside the panel (direct edits to .env/dialplan)."""
    with _lock:
        cli = current_cli()
        last = _history_list(limit=1)
        prev = last[0]["new"] if last else ""
        if cli == prev:
            return False
        _history_add({"ts": int(time.time()), "old": prev, "new": cli,
                      "user": "direct-edit"})
        return True


def normalize_cli(raw):
    d = re.sub(r"[\s\-().]", "", str(raw).strip())
    if not re.fullmatch(r"\+?[0-9]{8,15}", d):
        raise ValueError("CLI must be 8-15 digits (spaces/dashes allowed, optional +)")
    return d.lstrip("+")


def normalize_number(raw):
    d = re.sub(r"[\s\-().]", "", str(raw).strip())
    if not re.fullmatch(r"\+?[0-9]{7,15}", d):
        raise ValueError("Number must be 7-15 digits (spaces/dashes allowed, optional +)")
    if d.startswith("+"):
        d = d[1:]
    elif d.startswith("00"):
        d = d[2:]
    elif d.startswith("0") and len(d) == 11:
        d = "92" + d[1:]  # PK national -> E.164 without +
    return d


def set_cli(new_cli):
    with _lock:
        old = current_cli()
        ext_txt = _read(EXT_FILE)
        env_txt = _read(ENV_FILE)

        new_ext, n_ext = EXT_CLI_LINE.subn(
            lambda m: m.group("prefix") + new_cli + m.group("suffix"), ext_txt, count=1)
        new_env, n_env = ENV_CLI_LINE.subn(
            lambda m: m.group("prefix") + new_cli, env_txt, count=1)
        if n_ext != 1 or n_env != 1:
            raise RuntimeError(
                f"config edit failed (extensions.conf matches={n_ext}, .env matches={n_env})")

        _backup(EXT_FILE)
        _backup(ENV_FILE)
        _write_inplace(EXT_FILE, new_ext)
        _write_inplace(ENV_FILE, new_env)

        reload_out = asterisk_cli("dialplan reload")
        shown = asterisk_cli("dialplan show outbound")
        ok = f"Set(OUTCLI={new_cli})" in shown
        if not ok:
            raise RuntimeError(f"reload did not pick up new CLI. Output:\n{shown[:600]}")

        _history_add({"ts": int(time.time()), "old": old, "new": new_cli,
                      "user": PANEL_USER})
    return {"old": old, "new": new_cli, "reload": reload_out[:200]}


def trunk_status():
    out = asterisk_cli("pjsip show aor adcom-aor")
    m = re.search(r"Contact:.*?(Avail|Unreachable|NonQual|Unknown)(?:\s+([\d.]+))?", out)
    if not m:
        return {"status": "Unknown", "rtt_ms": None}
    rtt = float(m.group(2)) if m.group(2) else None
    return {"status": m.group(1), "rtt_ms": rtt}


def active_channels():
    out = asterisk_cli("core show channels concise")
    return len([ln for ln in out.splitlines() if ln.strip()])


def originate(number):
    cli = current_cli()
    # Run through the [outbound] dialplan so the pinned CLI is applied.
    asterisk_cli(f"channel originate Local/{number}@outbound "
                 f"application Playback(hello-world)")
    return {"dialed": number, "cli": cli}


def state():
    _history_sync()
    return {
        "cli": current_cli(),
        "trunk": trunk_status(),
        "channels": active_channels(),
        "history": _history_list(),
    }


# --------------------------------------------------------------------------- http

def _rate_ok(bucket, ip, limit, window):
    now = time.time()
    q = bucket[ip]
    while q and q[0] < now - window:
        q.popleft()
    if len(q) >= limit:
        return False
    q.append(now)
    return True


class Handler(BaseHTTPRequestHandler):
    server_version = "SipCliPanel/1.0"
    protocol_version = "HTTP/1.1"

    # -- helpers ------------------------------------------------------------
    def _security_headers(self):
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")

    def _json(self, obj, status=200):
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self._security_headers()
        self.end_headers()
        self.wfile.write(body)

    def _error(self, status, msg):
        self._json({"error": msg}, status)

    def _body(self):
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_BODY:
            raise ValueError("bad body size")
        raw = self.rfile.read(length)
        obj = json.loads(raw.decode("utf-8"))
        if not isinstance(obj, dict):
            raise ValueError("body must be a JSON object")
        return obj

    def _session_ok(self):
        cookie = self.headers.get("Cookie", "")
        m = re.search(rf"{COOKIE_NAME}=([A-Za-z0-9_\-]+)", cookie)
        if not m:
            return False
        tok = m.group(1)
        exp = _sessions.get(tok)
        if not exp or exp < time.time():
            _sessions.pop(tok, None)
            return False
        return True

    def _client_ip(self):
        fwd = self.headers.get("X-Forwarded-For", "")
        return fwd.split(",")[0].strip() or self.client_address[0]

    def log_message(self, fmt, *args):  # quiet default access log
        pass

    # -- routes -------------------------------------------------------------
    def do_GET(self):
        try:
            if self.path in ("/", "/index.html"):
                return self._serve_index()
            if self.path == "/api/state":
                return self._api_state()
            self._error(404, "not found")
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            try:
                self._error(500, str(e))
            except Exception:
                pass

    def do_POST(self):
        ip = self._client_ip()
        try:
            if self.path == "/api/login":
                if not _rate_ok(_login_rate, ip, 8, 300):
                    return self._error(429, "too many attempts, wait a few minutes")
                return self._api_login()
            if not _rate_ok(_rate, ip, 60, 60):
                return self._error(429, "rate limited")
            if not self._session_ok():
                return self._error(401, "not signed in")
            if self.path == "/api/cli":
                return self._api_set_cli()
            if self.path == "/api/call":
                return self._api_call()
            if self.path == "/api/logout":
                return self._api_logout()
            self._error(404, "not found")
        except ValueError as e:
            self._error(400, str(e))
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            try:
                self._error(500, str(e))
            except Exception:
                pass

    def _serve_index(self):
        try:
            with open(INDEX_FILE, "rb") as f:
                body = f.read()
        except OSError:
            return self._error(500, "index.html missing")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-cache")
        self._security_headers()
        self.send_header("Content-Security-Policy",
                         "default-src 'self'; script-src 'unsafe-inline'; "
                         "style-src 'unsafe-inline'; img-src 'self' data:; "
                         "connect-src 'self'; frame-ancestors 'none'")
        self.end_headers()
        self.wfile.write(body)

    def _api_login(self):
        body = self._body()
        user = str(body.get("username", ""))
        password = str(body.get("password", ""))
        user_ok = hmac.compare_digest(user, PANEL_USER)
        pass_ok = hmac.compare_digest(password, PANEL_PASSWORD)
        if not (user_ok and pass_ok):
            return self._error(401, "wrong username or password")
        tok = secrets.token_urlsafe(32)
        _sessions[tok] = time.time() + SESSION_TTL
        # opportunistic cleanup
        now = time.time()
        for t in [t for t, e in _sessions.items() if e < now]:
            _sessions.pop(t, None)
        self.send_response(200)
        self.send_header("Set-Cookie",
                         f"{COOKIE_NAME}={tok}; HttpOnly; SameSite=Strict; "
                         f"Path=/; Max-Age={SESSION_TTL}; Secure")
        self._json(state())

    def _api_logout(self):
        m = re.search(rf"{COOKIE_NAME}=([A-Za-z0-9_\-]+)", self.headers.get("Cookie", ""))
        if m:
            _sessions.pop(m.group(1), None)
        self.send_response(200)
        self.send_header("Set-Cookie",
                         f"{COOKIE_NAME}=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0")
        self._json({"ok": True})

    def _api_state(self):
        if not self._session_ok():
            return self._error(401, "not signed in")
        self._json(state())

    def _api_set_cli(self):
        body = self._body()
        cli = normalize_cli(body.get("cli", ""))
        self._json({"ok": True, **set_cli(cli)})

    def _api_call(self):
        body = self._body()
        number = normalize_number(body.get("number", ""))
        self._json({"ok": True, **originate(number)})


def main():
    if not PANEL_PASSWORD:
        raise SystemExit("PANEL_PASSWORD env var must be set")
    for path in (EXT_FILE, ENV_FILE):
        if not os.path.isfile(path):
            raise SystemExit(f"missing mounted file: {path}")
    os.makedirs(BACKUP_DIR, exist_ok=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
