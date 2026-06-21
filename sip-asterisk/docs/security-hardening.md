# Security Hardening — sip.polytronx.com

A misconfigured public SIP server can generate large fraud bills. Apply these
controls before or together with go-live.

## Already enforced by this stack

- **Provider IP whitelist only** — `pjsip.conf` `type=identify` matches the
  provider signaling IP; UFW allows `5060`/RTP only from provider IPs.
- **No anonymous/guest SIP** — no anonymous endpoint exists.
- **AMI disabled** — `manager.conf` `enabled=no` (port 5038 never exposed).
- **HTTP/ARI disabled** — `http.conf` `enabled=no`.
- **CLI enforced** — `[outbound]` always sets `CALLERID(num)=AUTHORIZED_CLI`.
- **Overload guard** — `asterisk.conf` `maxcalls`/`maxload`.
- **Least privilege** — Asterisk runs as the `asterisk` user, not root.
- **Log isolation** — dedicated `security` log channel for Fail2ban.

## Firewall (Phase 4)

- SSH `22` and NPM admin `81`: `ADMIN_IP` only.
- SIP `5060` and RTP `10000-20000`: provider IPs only.
- Public: only `80`/`443` (NPM web).
- Prefer the hosting provider's external firewall in addition to UFW, because
  Docker can bypass UFW for published ports.

## Fail2ban (Phase 11)

```bash
apt update && apt install -y fail2ban
cp fail2ban/jail.local /etc/fail2ban/jail.local
cp fail2ban/filter.d/asterisk-security.conf /etc/fail2ban/filter.d/
# IMPORTANT: add your ADMIN_IP to `ignoreip` in jail.local
systemctl enable --now fail2ban
fail2ban-client status
fail2ban-client status asterisk-security
```
The jail reads `/opt/stacks/sip-asterisk/logs/security` (the bind-mounted
Asterisk security log) and bans IPs after repeated failures.

## Dialplan / provider fraud controls

Server side (add as needed in `extensions.conf`):
- Max call duration (e.g. `Set(TIMEOUT(absolute)=3600)`).
- Allowed country prefixes only; block premium/international unless required.
- After-hours block if not needed.

Provider side (request explicitly):
- Max concurrent channels and max CPS.
- Daily spend cap + balance alerts.
- International disabled by default; premium destinations disabled.
- CLI enforcement (reject unauthorized CLI).

## Ongoing

- Keep the host and image updated; rebuild periodically:
  `docker compose build --pull && docker compose up -d`.
- Review `./logs/security`, CDRs, and `fail2ban-client status` regularly.
- TLS/SRTP (`5061`) later if the provider supports it.
- Never expose AMI/ARI/admin GUIs publicly.
