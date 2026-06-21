# RUNBOOK — sip.polytronx.com Asterisk Trunk (A → Z)

Full command runbook. Run phases in order. Commands marked **[VPS]** run on the
server (`/opt/stacks/sip-asterisk`), **[LOCAL]** on your PC, **[PROVIDER]** are
requests to the SIP trunk provider.

---

## Phase 0 — Provider requirements  [PROVIDER]

Collect from the provider before touching the VPS (see
[provider-onboarding.md](provider-onboarding.md)):

- Signaling IP(s) to whitelist, RTP/media IP(s)
- Gateway / outbound proxy IP, SIP port (usually 5060/UDP)
- Number format (E.164), codecs, DTMF (CLI is pass-through; provider screens it)
- Max channels / CPS, allowed destinations, test number, CDR portal

Then on the VPS:

```bash
cp .env.example .env
nano .env   # PROVIDER_GATEWAY_IP, PROVIDER_SIGNALING_IP(S), PROVIDER_RTP_IPS,
            # ADMIN_IP   (no AUTHORIZED_CLI — CLI is pass-through)
```

> Do not continue to production calling until the provider IPs are known and they have whitelisted our IP.

---

## Phase 1 — SSH access  [LOCAL]

```bash
# Linux/macOS
bash scripts/00-ssh-discovery.sh
ssh -o IdentitiesOnly=yes root@185.252.233.186
```
```powershell
# Windows
./scripts/00-ssh-discovery.ps1
ssh -i "$env:USERPROFILE\.ssh\YOUR_KEY_FILE" -o IdentitiesOnly=yes root@185.252.233.186
```

Copy the stack to the VPS once connected, e.g.:
```bash
rsync -avz ./sip-asterisk/ root@185.252.233.186:/opt/stacks/sip-asterisk/
```

---

## Phase 2 — VPS preflight + backups + snapshot  [VPS]

```bash
cd /opt/stacks/sip-asterisk
bash scripts/01-preflight-audit.sh    # audits + writes /root/pre-sip-backup
```
Then **take a VPS provider snapshot** from your hosting panel.

Confirm SIP ports are free (no output = good):
```bash
ss -tulpn | grep -E ':5060|:5061|:10000|:20000'
```

---

## Phase 3 — DNS  [VPS or LOCAL]

```bash
bash scripts/02-dns-validation.sh
# expect: sip.polytronx.com -> 185.252.233.186
```

---

## Phase 4 — Firewall / ports  [VPS]

```bash
bash scripts/03-firewall-setup.sh           # dry-run, shows the plan
bash scripts/03-firewall-setup.sh --apply   # applies + enables UFW
ufw status verbose
```
SSH (22) is allowed only from `ADMIN_IP`. Keep the provider console/snapshot
ready in case of lockout. Docker uses host networking here, so also enable your
hosting provider's external firewall/security group if available.

---

## Phase 5 — Stack scaffolding  [VPS]

Already present in `/opt/stacks/sip-asterisk` (`Dockerfile`,
`docker-compose.yml`, `docker-entrypoint.sh`). Directory ownership:
```bash
chown -R root:root /opt/stacks/sip-asterisk
chmod -R 750 /opt/stacks/sip-asterisk
```

---

## Phase 6 — Asterisk configuration  [VPS]

Configs live in `config-templates/` with `__TOKEN__` placeholders and are
rendered to `etc/` from `.env`:
```bash
bash scripts/render-config.sh    # writes etc/*.conf, fails on leftover CHANGE_ME
ls etc/
```
For multiple provider signaling IPs, add extra `match=` lines in
`config-templates/pjsip.conf`, then re-render.

---

## Phase 7 — Build, deploy, verify  [VPS]

```bash
bash scripts/04-deploy.sh             # render + build + up -d
docker compose ps
docker logs -f sip-asterisk

bash scripts/05-verify-asterisk.sh    # transports/endpoints/aors/identifies
```
Reload after later edits:
```bash
docker exec -it sip-asterisk asterisk -rx "core reload"
docker exec -it sip-asterisk asterisk -rx "pjsip reload"
```

---

## Phase 8 — NPM web/admin  [NPM]

Keep Asterisk off 80/443. Restrict NPM admin `:81` to `ADMIN_IP`. Details:
[npm-configuration.md](npm-configuration.md).

---

## Phase 9 — Provider onboarding  [PROVIDER]

Send the onboarding request (whitelist `185.252.233.186`, authorize CLI) from
[provider-onboarding.md](provider-onboarding.md). Wait for confirmation.

---

## Phase 10 — Testing  [VPS]

```bash
bash scripts/06-testing-checklist.sh
docker exec -it sip-asterisk sngrep                 # live SIP trace
docker exec -it sip-asterisk asterisk -rx "pjsip set logger on"
```
Order: OPTIONS/qualify → outbound to provider test number → call your mobile →
two-way audio → CLI passes through as your app sent it → provider CDR.
Full matrix: [testing-checklist.md](testing-checklist.md).

---

## Phase 11 — Security hardening + Fail2ban  [VPS]

```bash
apt update && apt install -y fail2ban
cp fail2ban/jail.local /etc/fail2ban/jail.local
cp fail2ban/filter.d/asterisk-security.conf /etc/fail2ban/filter.d/
# add your ADMIN_IP to ignoreip in jail.local, then:
systemctl enable --now fail2ban
fail2ban-client status
```
Full checklist: [security-hardening.md](security-hardening.md).

---

## Phase 12 — Backups  [VPS]

```bash
bash scripts/07-backup.sh
rsync -avz backup/ user@backup-server:/backups/sip-asterisk/
```
Schedule daily, e.g. cron: `0 3 * * * cd /opt/stacks/sip-asterisk && bash scripts/07-backup.sh`.

---

## Phase 13 — Monitoring  [VPS]

```bash
bash scripts/08-monitoring.sh
docker stats sip-asterisk
```

---

## Phase 14 — Rollback  [VPS]

```bash
bash scripts/09-rollback.sh      # confirms, then docker compose down
ufw status numbered              # delete SIP rules by number if needed
```
If unreachable: restore the snapshot or `ufw disable` from the provider console.

---

## Phase 15 — Go-live order (summary)

1. Provider requirements confirmed → `.env` filled.
2. SSH verified; stack copied to `/opt/stacks/sip-asterisk`.
3. Snapshot + preflight backups taken.
4. DNS correct.
5. Firewall applied (admin + provider IPs only).
6. Config rendered; container built and running.
7. Provider whitelisted our IP (IP-auth); CLI/number screening is provider-side.
8. OPTIONS OK → first call → two-way audio → CLI passes through → CDR confirmed.
9. Fail2ban + fraud controls active.
10. Backups + monitoring scheduled; SSH/NPM/admin locked down; config documented.
