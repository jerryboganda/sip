# Nginx Proxy Manager (NPM) — sip.polytronx.com

NPM handles **web/admin only** (HTTP/HTTPS), never the SIP/RTP media path.
SIP `5060` and RTP `10000-20000` are exposed directly via host networking +
strict UFW rules, not proxied through NPM.

## Rules

1. Keep the existing NPM container unchanged.
2. Do **not** bind Asterisk to ports 80/443.
3. Restrict the NPM admin UI (`:81`) to your `ADMIN_IP` (or VPN).
4. Do not expose Asterisk AMI (`5038`) or HTTP/ARI (`8088/8089`) — both are
   disabled in this stack.

## Recommended hostnames

```
sip.polytronx.com   -> SIP DNS (A record) + optional HTTPS landing page via NPM
pbx.polytronx.com   -> optional admin GUI later, behind an NPM access list
```

If you must use only `sip.polytronx.com`:

```
sip.polytronx.com:443           -> NPM HTTPS (web)
sip.polytronx.com:5060          -> Asterisk SIP (direct, firewalled)
sip.polytronx.com:10000-20000   -> Asterisk RTP (direct, firewalled)
```

## Why not proxy SIP/RTP through NPM

NPM centers on 80/443/81 web proxying. While the Nginx `stream` module can
proxy raw TCP/UDP, troubleshooting SIP signaling and a large RTP UDP range is
far cleaner when exposed directly with strict firewall rules. Keep media off
NPM.

## If you add a PBX web UI later

- Use a separate subdomain (`pbx.polytronx.com`).
- Add an NPM **Access List** (allow your admin IP / basic auth).
- Force HTTPS; never expose the admin UI to the public internet.
