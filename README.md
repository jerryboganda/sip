# sip.polytronx.com — Asterisk 22 SIP Trunk (Production)

Complete, phased, ready-to-deploy implementation of the deployment plan in
[Domain_ sip.md](Domain_%20sip.md). Everything is materialized as real files:
the Docker/Asterisk stack, all configs, every operational script, security
hardening, and a phased runbook.

- **Target VPS:** `185.252.233.186` (existing Docker + Nginx Proxy Manager host)
- **Domain:** `sip.polytronx.com`
- **Engine:** Asterisk 22 (Sangoma/FreePBX Debian 12 packages) in its own Docker
  Compose stack with `network_mode: host`.
- **Auth model:** provider **IP whitelist** (no SIP registration). Caller ID and
  numbers are passed through unmodified — the provider screens CLI on their side.
- **NPM role:** web/admin (80/443/81) only — never the SIP/RTP media path.

> Deploy target on the VPS: copy the `sip-asterisk/` folder to
> `/opt/stacks/sip-asterisk`.

---

## Two inputs only you can provide

This repo is 100% complete except for two things that are **physically external**
to this machine and must not be guessed:

1. **Provider values** → fill into `sip-asterisk/.env`
   (gateway IP, signaling IP(s), RTP IP(s)). See
   [docs/provider-onboarding.md](sip-asterisk/docs/provider-onboarding.md).
2. **SSH execution on the VPS** → you run the `scripts/` on your server.
   Never paste your private SSH key anywhere.

Everything else is automated by the scripts below.

---

## Phases (A → Z)

Each phase maps to the original plan stages and to a concrete artifact/command.

| Phase | What | Plan stage | Artifact / command | Where |
|------:|------|-----------|--------------------|-------|
| **0** | Gather provider requirements (IPs) | §2, §3 (info), §12 | `docs/provider-onboarding.md`, fill `.env` | off-server |
| **1** | Find/test the SSH key | §4 | `scripts/00-ssh-discovery.{sh,ps1}` | local PC |
| **2** | VPS preflight audit + backups + **snapshot** | §5 | `scripts/01-preflight-audit.sh` | VPS |
| **3** | DNS validation | §6 | `scripts/02-dns-validation.sh` | anywhere |
| **4** | Firewall / ports (UFW) | §7 | `scripts/03-firewall-setup.sh` | VPS |
| **5** | Stack scaffolding (dirs, Dockerfile, compose) | §5–§7 | `Dockerfile`, `docker-compose.yml`, `docker-entrypoint.sh` | VPS |
| **6** | Asterisk config (pjsip/rtp/dialplan) | §8, §9 | `config-templates/*.conf` → `render-config.sh` | VPS |
| **7** | Build, deploy, verify | §10 | `scripts/04-deploy.sh`, `scripts/05-verify-asterisk.sh` | VPS |
| **8** | NPM web/admin (keep off SIP/RTP) | §11 | `docs/npm-configuration.md` | VPS/NPM |
| **9** | Provider onboarding (whitelist our IP) | §12 | `docs/provider-onboarding.md` | provider |
| **10** | Testing (OPTIONS, first call, audio, CLI, CDR) | §13 | `scripts/06-testing-checklist.sh`, `docs/testing-checklist.md` | VPS |
| **11** | Security hardening + Fail2ban | §14 | `docs/security-hardening.md`, `fail2ban/` | VPS |
| **12** | Backups | §15 | `scripts/07-backup.sh` | VPS |
| **13** | Monitoring | §16 | `scripts/08-monitoring.sh` | VPS |
| **14** | Rollback readiness | §17 | `scripts/09-rollback.sh` | VPS |
| **15** | Go-live order + documentation | §21–§23 | `docs/RUNBOOK.md` (this set) | — |

Full step-by-step commands: **[docs/RUNBOOK.md](sip-asterisk/docs/RUNBOOK.md)**.

---

## Quickstart (on the VPS, after Phases 0–4)

```bash
# 0. Put this folder at /opt/stacks/sip-asterisk and cd into it
cd /opt/stacks/sip-asterisk

# 1. Configure
cp .env.example .env
nano .env                      # fill provider IPs + ADMIN_IP (CLI is pass-through)

# 2. Firewall (dry-run first, then apply)
bash scripts/03-firewall-setup.sh
bash scripts/03-firewall-setup.sh --apply

# 3. Render config, build, start
bash scripts/04-deploy.sh

# 4. Verify
bash scripts/05-verify-asterisk.sh
docker logs -f sip-asterisk
```

---

## Repository layout

```
sip-asterisk/
  .env.example            # fill -> .env (provider IPs, admin IP)
  .gitattributes          # forces LF for shell/conf (container safety)
  .gitignore
  Dockerfile              # Asterisk 22 (Sangoma/FreePBX Debian 12 repo)
  docker-entrypoint.sh    # seeds volumes, drops privileges (LF endings!)
  docker-compose.yml      # host networking, healthcheck, log rotation
  config-templates/       # source-of-truth Asterisk configs (with __TOKENS__)
    asterisk.conf  modules.conf  logger.conf  manager.conf  http.conf
    cdr.conf  rtp.conf  pjsip.conf  extensions.conf
  scripts/
    render-config.sh      # config-templates/*.conf -> etc/*.conf from .env
    00-ssh-discovery.sh / .ps1
    01-preflight-audit.sh
    02-dns-validation.sh
    03-firewall-setup.sh
    04-deploy.sh
    05-verify-asterisk.sh
    06-testing-checklist.sh
    07-backup.sh
    08-monitoring.sh
    09-rollback.sh
  fail2ban/
    jail.local
    filter.d/asterisk-security.conf
  docs/
    RUNBOOK.md            # full A-Z command runbook
    provider-onboarding.md
    security-hardening.md
    testing-checklist.md
    npm-configuration.md
```

---

## Guardrails — what must NOT be done

- Do **not** expose SIP `5060` or RTP `10000-20000` to the whole internet when
  provider IPs are known — allow only those IPs.
- Do **not** expose Asterisk AMI `5038` or the HTTP/ARI server (both disabled here).
- Do **not** paste private SSH keys into chat, tickets, or files.
- Do **not** install native FreePBX on this shared Docker/NPM host without a
  snapshot and conflict review.
- CLI / number screening is the **provider's** responsibility (full pass-through
  here) — ensure your CLI usage complies with your provider agreement and local law.
- Destination / international / premium policy is enforced **provider-side** (no
  local blocks).

A misconfigured public SIP server can generate large fraud bills. Complete
Phase 11 (security hardening) before/with go-live.
