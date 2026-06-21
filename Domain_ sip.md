

**Domain:** `sip.polytronx.com` **Production VPS IP:** `185.252.233.186` **Existing environment:** Docker / Docker Desktop, Nginx Proxy Manager, many other projects already running **Goal:** Provider whitelists your VPS IP, then your server sends/receives calls through an IP-authenticated SIP trunk with only authorized caller IDs.

I am assuming **NPM \= Nginx Proxy Manager**. NPM should handle only HTTP/HTTPS web access, not the SIP/RTP media path. NPM normally binds ports **80, 443, and 81**, while SIP/RTP requires separate direct port handling. ([Nginx Proxy Manager](https://nginxproxymanager.com/setup/))

---

# 1\. Recommended production architecture

For this VPS, the safest architecture is:

sip.polytronx.com

        |

        | DNS A record

        v

185.252.233.186 VPS

        |

        \+-- Nginx Proxy Manager

        |     \+-- HTTPS admin/web access only, if needed

        |

        \+-- Docker Compose stack: sip-asterisk

              \+-- Asterisk 22 SIP engine

              \+-- Direct SIP port: 5060 UDP/TCP or 5061 TLS

              \+-- Direct RTP range: 10000-20000 UDP

              \+-- Provider IP whitelist only

For your shared VPS, I would **not install FreePBX natively on the host** as the first choice, because the official FreePBX install path is a Debian 12 server/VM install script and it installs a full PBX stack on the machine. That can interfere with an existing Docker/NPM host that already has web, database, firewall, and port usage. FreePBX’s own instructions describe Debian 12 plus the official install script, and the GitHub installer says it installs FreePBX on top of vanilla Debian 12.x. ([FreePBX \- Let Freedom Ring](https://www.freepbx.org/get-started/)) ([GitHub](https://github.com/FreePBX/sng_freepbx_debian_install))

The cleanest first production deployment on your existing VPS is **Asterisk 22 in its own Docker Compose stack**, with `network_mode: host` so SIP/RTP can bind directly to the VPS network. Docker’s own documentation says host networking shares the host network namespace and is useful where a container must handle a large range of ports, which is exactly the RTP case. ([Docker Documentation](https://docs.docker.com/engine/network/drivers/host/))

---

# 2\. Important caller ID rule

Your server can send caller ID headers, but it must only send **caller IDs / CLIs that your SIP trunk provider has authorized for your account**. Correct CLI is not achieved by “owning the VPS”; it is achieved by the provider allowing your DID/CLI and passing it downstream. Caller ID authentication and spoofing controls are regulated in many networks; for example, the FCC describes STIR/SHAKEN caller ID authentication for IP networks and also defines spoofing as deliberately falsifying caller ID information. ([Federal Communications Commission](https://www.fcc.gov/call-authentication?utm_source=chatgpt.com)) ([Federal Communications Commission](https://www.fcc.gov/consumers/guides/spoofing?utm_source=chatgpt.com))

So in this plan:

Allowed:

\- Your business number

\- Your purchased DID

\- Your verified CLI approved by the SIP trunk provider

Not allowed:

\- Random customer numbers

\- Bank/government/company numbers you do not control

\- Any CLI not contractually approved by the provider

---

# 3\. Required information before deployment

Before touching the live VPS, collect this from the SIP trunk provider:

| Item | Required value |
| :---- | :---- |
| Provider signaling IPs | Example: `x.x.x.x/32`, `y.y.y.y/32` |
| Provider RTP/media IPs | Sometimes same as signaling, sometimes separate |
| IP authentication confirmation | Provider must whitelist `185.252.233.186` |
| SIP port | Usually `5060 UDP`; sometimes `5060 TCP` or `5061 TLS` |
| Outbound proxy / gateway | IP or FQDN from provider |
| Allowed caller IDs | Exact DID/CLI list they permit |
| Number format | Usually E.164, for example `923001234567` or `+923001234567` depending provider |
| Codecs | Usually `alaw`, `ulaw`, sometimes `g729`, `opus` |
| DTMF mode | Usually RFC4733 / RTP events |
| Max channels | Concurrent call limit |
| Max CPS | Calls per second limit |
| Allowed destinations | Pakistan only, international, premium blocked, etc. |
| Test number | Provider echo test or test destination |
| CDR portal/API | For billing and debugging |

Do not proceed to production calling until you have the provider IPs and authorized CLI list.

---

# 4\. Stage 1 — SSH access and key discovery

I cannot directly search your local PC from here, and you should never paste your private SSH key into chat. Use these commands on the PC where the key is stored.

## Linux/macOS terminal

ls \-la \~/.ssh

ssh-add \-l

grep \-R "185.252.233.186\\|sip.polytronx.com" \~/.ssh/config \~/.ssh/\* 2\>/dev/null

for k in \~/.ssh/id\_\* \~/.ssh/\*.pem \~/.ssh/\*.key 2\>/dev/null; do

  ssh-keygen \-y \-f "$k" \>/dev/null 2\>&1 && echo "Possible SSH private key: $k"

done

Test connection:

ssh \-o IdentitiesOnly=yes root@185.252.233.186

If you find the key path, use:

ssh \-i \~/.ssh/YOUR\_KEY\_FILE \-o IdentitiesOnly=yes root@185.252.233.186

## Windows PowerShell

dir $env:USERPROFILE\\.ssh

ssh-add \-l

Select-String \-Path "$env:USERPROFILE\\.ssh\\config","$env:USERPROFILE\\.ssh\\\*" \`

  \-Pattern "185.252.233.186|sip.polytronx.com" \`

  \-ErrorAction SilentlyContinue

Test connection:

ssh \-i "$env:USERPROFILE\\.ssh\\YOUR\_KEY\_FILE" \-o IdentitiesOnly=yes root@185.252.233.186

---

# 5\. Stage 2 — VPS preflight audit

After SSH login:

hostnamectl

cat /etc/os-release

date

uptime

whoami

ip addr

ip route

df \-h

free \-h

Check Docker and Compose:

docker version

docker compose version

docker info | sed \-n '1,80p'

Check running projects:

docker ps \--format "table {{.Names}}\\t{{.Image}}\\t{{.Ports}}\\t{{.Status}}"

docker network ls

docker volume ls

Check ports already in use:

ss \-tulpn

ss \-tulpn | egrep ':80|:443|:81|:22|:5060|:5061|:10000|:20000'

Backup the current Docker/NPM state before any change:

mkdir \-p /root/pre-sip-backup

docker ps \> /root/pre-sip-backup/docker-ps.txt

docker network ls \> /root/pre-sip-backup/docker-networks.txt

docker volume ls \> /root/pre-sip-backup/docker-volumes.txt

ss \-tulpn \> /root/pre-sip-backup/ports-before.txt

iptables-save \> /root/pre-sip-backup/iptables-before.rules 2\>/dev/null || true

nft list ruleset \> /root/pre-sip-backup/nft-before.rules 2\>/dev/null || true

Also take a **VPS snapshot** from your hosting provider panel before changing firewall or ports.

---

# 6\. Stage 3 — DNS validation

Confirm `sip.polytronx.com` points to the production VPS:

dig \+short sip.polytronx.com A

Expected result:

185.252.233.186

Also check public DNS from a separate resolver:

dig @1.1.1.1 \+short sip.polytronx.com A

dig @8.8.8.8 \+short sip.polytronx.com A

If the result is not `185.252.233.186`, fix DNS before SIP provider testing.

---

# 7\. Stage 4 — Port and firewall plan

## Correct port design

| Service | Port | Protocol | Source allowed | Notes |
| :---- | ----: | :---- | :---- | :---- |
| SSH | 22 | TCP | Your admin IP only | Keep open during setup |
| NPM HTTP | 80 | TCP | Public | For NPM / Let’s Encrypt |
| NPM HTTPS | 443 | TCP | Public | Web access only |
| NPM Admin | 81 | TCP | Admin IP/VPN only | Never public |
| SIP signaling | 5060 | UDP | Provider IPs only | Main SIP trunk port |
| SIP signaling optional | 5060 | TCP | Provider IPs only | Only if provider needs TCP |
| SIP TLS optional | 5061 | TCP | Provider IPs only | Only if using TLS |
| RTP media | 10000-20000 | UDP | Provider RTP IPs only | Voice media |
| Asterisk AMI | 5038 | TCP | Localhost/private only | Never public |
| Asterisk HTTP/ARI | 8088/8089 | TCP | Localhost/private only | Never public unless secured |

Asterisk’s NAT/PJSIP configuration must advertise the public IP for signaling and RTP. Asterisk documentation specifically highlights `local_net`, `external_media_address`, `external_signaling_address`, and `direct_media` as key NAT options for res\_pjsip. ([Asterisk Documentation](https://docs.asterisk.org/Configuration/Channel-Drivers/SIP/Configuring-res_pjsip/Configuring-res_pjsip-to-work-through-NAT/))

## Example UFW firewall plan

Replace these placeholders before running:

ADMIN\_IP="YOUR\_ADMIN\_PUBLIC\_IP"

PROVIDER\_SIGNAL\_IP="PROVIDER\_SIGNALING\_IP"

PROVIDER\_RTP\_IP="PROVIDER\_RTP\_IP"

Rules:

ufw status verbose

ufw default deny incoming

ufw default allow outgoing

ufw allow from "$ADMIN\_IP" to any port 22 proto tcp

ufw allow 80/tcp

ufw allow 443/tcp

ufw allow from "$ADMIN\_IP" to any port 81 proto tcp

ufw allow from "$PROVIDER\_SIGNAL\_IP" to any port 5060 proto udp

ufw allow from "$PROVIDER\_SIGNAL\_IP" to any port 5060 proto tcp

ufw allow from "$PROVIDER\_RTP\_IP" to any port 10000:20000 proto udp

ufw status numbered

Only enable/reload after confirming SSH is allowed:

ufw enable

ufw status verbose

For a Docker-heavy server, the best practice is also to use your VPS provider’s external firewall/security group if available, because Docker can modify host firewall behavior when publishing ports.

---

# 8\. Stage 5 — SIP stack directory structure

Create a separate project path so it does not mix with other projects:

mkdir \-p /opt/stacks/sip-asterisk

cd /opt/stacks/sip-asterisk

mkdir \-p etc logs spool lib recordings backup

Recommended ownership:

chown \-R root:root /opt/stacks/sip-asterisk

chmod \-R 750 /opt/stacks/sip-asterisk

---

# 9\. Stage 6 — Docker Compose deployment design

Use one dedicated stack:

services:

  asterisk:

    build: .

    container\_name: sip-asterisk

    network\_mode: "host"

    restart: unless-stopped

    volumes:

      \- ./etc:/etc/asterisk

      \- ./logs:/var/log/asterisk

      \- ./spool:/var/spool/asterisk

      \- ./lib:/var/lib/asterisk

      \- ./recordings:/var/spool/asterisk/monitor

    environment:

      TZ: Asia/Karachi

    ulimits:

      nofile:

        soft: 65535

        hard: 65535

    logging:

      driver: json-file

      options:

        max-size: "50m"

        max-file: "5"

`network_mode: "host"` is deliberate here. In host networking, Docker port publishing is ignored because the container shares the host’s network namespace, and Docker documents this as useful for large port ranges. ([Docker Documentation](https://docs.docker.com/engine/network/drivers/host/))

Docker’s production Compose guidance also recommends production-specific changes such as restart policies, port binding choices, environment differences, and log aggregation/operational configuration. ([Docker Documentation](https://docs.docker.com/compose/how-tos/production/))

---

# 10\. Stage 7 — Asterisk build plan

Use Asterisk 22 from Sangoma’s Debian 12 repository rather than a random Docker Hub image. Sangoma documents Asterisk 22 packages for Debian 12 using the FreePBX package repository, including `asterisk22`, `asterisk22-core`, and `asterisk22-configs`. ([Sangoma KB](https://sangomakb.atlassian.net/wiki/spaces/OpenSource/pages/544079886/Open%2BSource%2B-%2BAsterisk%2B22%2Bon%2BDebian%2B12%2Bwith%2Bofficial%2BSangoma%2BFreePBX%2Bpackage%2Brepository))

Example Dockerfile direction:

FROM debian:12-slim

ENV DEBIAN\_FRONTEND=noninteractive

ENV TZ=Asia/Karachi

RUN apt-get update && apt-get install \-y \--no-install-recommends \\

    ca-certificates gnupg software-properties-common wget curl \\

    procps iproute2 dnsutils tcpdump sngrep nano less \\

 && addgroup \--system asterisk \\

 && adduser \--system \--ingroup asterisk asterisk \\

 && wget \-O /tmp/aptly-pubkey.asc http://deb.freepbx.org/gpg/aptly-pubkey.asc \\

 && gpg \--dearmor \--yes \-o /etc/apt/trusted.gpg.d/freepbx.gpg /tmp/aptly-pubkey.asc \\

 && add-apt-repository \-y \-S "deb \[ arch=amd64 \] http://deb.freepbx.org/freepbx17-prod bookworm main" \\

 && apt-get update \\

 && apt-get install \-y \--no-install-recommends \\

    asterisk22 asterisk22-core asterisk22-configs libxslt1.1 liburiparser1 \\

 && apt-get clean \\

 && rm \-rf /var/lib/apt/lists/\*

CMD \["/usr/sbin/asterisk", "-f", "-U", "asterisk", "-G", "asterisk", "-vvv"\]

Build and start:

cd /opt/stacks/sip-asterisk

docker compose build

docker compose up \-d

docker ps | grep sip-asterisk

docker logs \-f sip-asterisk

---

# 11\. Stage 8 — Asterisk SIP configuration

Create or edit:

nano /opt/stacks/sip-asterisk/etc/pjsip.conf

Base transport:

\[global\]

type=global

user\_agent=sip.polytronx.com

\[transport-udp\]

type=transport

protocol=udp

bind=0.0.0.0:5060

local\_net=127.0.0.0/8

local\_net=10.0.0.0/8

local\_net=172.16.0.0/12

local\_net=192.168.0.0/16

external\_signaling\_address=185.252.233.186

external\_media\_address=185.252.233.186

Provider IP-auth trunk example:

\[provider-aor\]

type=aor

contact=sip:PROVIDER\_GATEWAY\_IP:5060

qualify\_frequency=60

\[provider-endpoint\]

type=endpoint

transport=transport-udp

context=from-provider

disallow=all

allow=alaw

allow=ulaw

aors=provider-aor

direct\_media=no

rtp\_symmetric=yes

force\_rport=yes

rewrite\_contact=yes

trust\_id\_inbound=yes

send\_pai=yes

from\_domain=sip.polytronx.com

outbound\_proxy=sip:PROVIDER\_GATEWAY\_IP\\;lr

\[provider-identify\]

type=identify

endpoint=provider-endpoint

match=PROVIDER\_SIGNALING\_IP/32

If the provider uses multiple signaling IPs:

match=PROVIDER\_SIGNALING\_IP\_1/32

match=PROVIDER\_SIGNALING\_IP\_2/32

match=PROVIDER\_SIGNALING\_IP\_3/32

Create RTP config:

nano /opt/stacks/sip-asterisk/etc/rtp.conf

\[general\]

rtpstart=10000

rtpend=20000

strictrtp=yes

Asterisk sample RTP config commonly documents `rtpstart` and `rtpend`, and Asterisk/FreePBX examples often use `10000-20000` for RTP. ([GitHub](https://github.com/asterisk/asterisk/blob/master/configs/samples/rtp.conf.sample?utm_source=chatgpt.com)) ([Sangoma KB](https://sangomakb.atlassian.net/wiki/spaces/PG/pages/38536497/NAT%2BConfiguration%2BFreePBX%2B12?utm_source=chatgpt.com))

---

# 12\. Stage 9 — Dialplan and authorized caller ID

Create:

nano /opt/stacks/sip-asterisk/etc/extensions.conf

Basic safe outbound context:

\[globals\]

AUTHORIZED\_CLI=YOUR\_PROVIDER\_APPROVED\_CALLER\_ID

\[outbound\]

exten \=\> \_X.,1,NoOp(Outbound call to ${EXTEN})

 same \=\> n,Set(CALLERID(num)=${AUTHORIZED\_CLI})

 same \=\> n,Set(CALLERID(name)=Polytronx)

 same \=\> n,Dial(PJSIP/${EXTEN}@provider-endpoint,60)

 same \=\> n,Hangup()

\[from-provider\]

exten \=\> \_X.,1,NoOp(Inbound call from provider to ${EXTEN})

 same \=\> n,Hangup()

Do not put unverified caller IDs here. Use only numbers approved by the trunk provider.

Later, if you add internal extensions or a dialer app, send calls into the `[outbound]` context only after authentication.

---

# 13\. Stage 10 — Reload and verify Asterisk

docker exec \-it sip-asterisk asterisk \-rvvv

Inside Asterisk CLI:

pjsip show transports

pjsip show endpoints

pjsip show aors

pjsip show identifies

core show channels

Reload after changes:

docker exec \-it sip-asterisk asterisk \-rx "core reload"

docker exec \-it sip-asterisk asterisk \-rx "pjsip reload"

Enable SIP debug during testing only:

docker exec \-it sip-asterisk asterisk \-rx "pjsip set logger on"

Turn it off after testing:

docker exec \-it sip-asterisk asterisk \-rx "pjsip set logger off"

---

# 14\. Stage 11 — NPM configuration

Use NPM only for web/admin access, not RTP.

Recommended:

sip.polytronx.com        \-\> SIP DNS \+ optional HTTPS landing page

pbx.polytronx.com        \-\> Optional admin GUI, restricted by NPM access list

If you must use only `sip.polytronx.com`, then:

sip.polytronx.com:443    \-\> NPM HTTPS

sip.polytronx.com:5060   \-\> Asterisk SIP direct

sip.polytronx.com:10000-20000 UDP \-\> Asterisk RTP direct

NPM can manage proxy hosts and SSL for web services, but it is not the right place to manage a large RTP UDP range. Nginx stream can proxy TCP/UDP at layer 4, but SIP/RTP production troubleshooting is much cleaner when SIP/RTP is exposed directly through strict firewall rules. Nginx’s stream module is for TCP/UDP proxying, while NPM’s standard setup is centered on ports 80/443/81 for web proxying/admin. ([NGINX Documentation](https://docs.nginx.com/nginx/admin-guide/load-balancer/tcp-udp-load-balancer/?utm_source=chatgpt.com)) ([Nginx Proxy Manager](https://nginxproxymanager.com/setup/))

For NPM:

1. Keep existing NPM container unchanged.  
2. Do not bind Asterisk to ports 80/443.  
3. Restrict NPM admin port `81` to your admin IP or VPN.  
4. If adding a PBX web UI later, create a separate subdomain and NPM access list.  
5. Do not expose Asterisk AMI `5038` publicly.

---

# 15\. Stage 12 — Provider onboarding

Send this to the SIP trunk provider:

Please whitelist our production SIP server:

Public IP: 185.252.233.186

FQDN: sip.polytronx.com

SIP signaling port: 5060 UDP

Optional SIP TCP: 5060 TCP only if required

RTP media range: 10000-20000 UDP

Authentication type: IP authentication / IP ACL

Allowed outbound CLI: \[list only provider-approved numbers\]

Preferred codecs: alaw, ulaw

DTMF: RFC4733

Ask the provider to confirm:

1\. Exact signaling IPs we must whitelist.

2\. Exact RTP/media IPs we must whitelist.

3\. Exact number format required for outbound dialing.

4\. Whether From, P-Asserted-Identity, or Remote-Party-ID should carry CLI.

5\. Whether they require SIP OPTIONS qualify.

6\. Whether they rewrite CLI or reject unauthorized CLI.

7\. Whether international/premium routes are disabled by default.

---

# 16\. Stage 13 — Testing checklist

## Network tests

dig \+short sip.polytronx.com A

ss \-tulpn | egrep ':5060|:5061|:10000|:20000'

docker logs \--tail=100 sip-asterisk

## SIP trace

docker exec \-it sip-asterisk sngrep

Or:

tcpdump \-ni any port 5060

tcpdump \-ni any udp portrange 10000-20000

## Asterisk tests

docker exec \-it sip-asterisk asterisk \-rx "pjsip show endpoint provider-endpoint"

docker exec \-it sip-asterisk asterisk \-rx "pjsip show contacts"

docker exec \-it sip-asterisk asterisk \-rx "core show channels"

## First call test

Test in this order:

1. Provider SIP OPTIONS response.  
2. Outbound call to provider test number.  
3. Outbound call to your own mobile.  
4. Verify audio both ways.  
5. Verify CLI display.  
6. Check provider CDR.  
7. Check Asterisk logs.  
8. Test a rejected unauthorized CLI to confirm the provider blocks it.  
9. Test max duration limit.  
10. Test blocked destinations.

Common failures:

| Symptom | Likely cause |
| :---- | :---- |
| `403 Forbidden` | IP not whitelisted or CLI not authorized |
| `401 Unauthorized` | Provider expects registration/auth, not IP-auth |
| `404` / `484` | Wrong dialed number format |
| Call connects but no audio | RTP firewall/NAT issue |
| One-way audio | RTP source IP/range mismatch |
| `488 Not Acceptable Here` | Codec mismatch |
| CLI wrong | Provider is overriding CLI or wrong header format |
| Random SIP scans | Firewall too open |

---

# 17\. Stage 14 — Security hardening

This is not optional. A public SIP server can generate large fraud bills if misconfigured. Asterisk’s own security documentation warns that improper configuration can allow unauthorized use and substantial charges. ([Asterisk Documentation](https://docs.asterisk.org/Deployment/Important-Security-Considerations/))

Apply these controls:

## SIP security

\- Provider IP whitelist only.

\- No anonymous inbound SIP.

\- No SIP guest calling.

\- No public AMI.

\- No public ARI.

\- No public admin GUI.

\- Strong internal extension passwords if extensions are added.

\- TLS/SRTP later if provider supports it.

FreePBX security guidance also recommends updates, Fail2ban, firewall whitelisting, HTTPS-only access, disabling anonymous/guest SIP, IP-based trunk authentication where supported, and blocking untrusted access to SSH/admin/SIP where possible. ([Sangoma KB](https://sangomakb.atlassian.net/wiki/spaces/FCD/pages/9699445/FreePBX%2BSecurity%2BBest%2BPractices))

## Fail2ban

Install on the host or as a sidecar only if logs are properly visible:

apt update

apt install \-y fail2ban

systemctl enable \--now fail2ban

fail2ban-client status

Fail2ban watches logs and can ban IPs after repeated failures by updating firewall rules. ([GitHub](https://github.com/fail2ban/fail2ban?utm_source=chatgpt.com))

## Dialplan fraud controls

Add:

\- Max call duration

\- Allowed country prefixes only

\- Premium-rate block

\- International block unless explicitly needed

\- After-hours block if not needed

\- Per-minute/channel limits at provider side

\- Daily spend alert at provider side

Ask provider to enable:

\- Max concurrent channels

\- Max CPS

\- Daily spend cap

\- International disabled by default

\- Premium destinations disabled

\- CLI enforcement

---

# 18\. Stage 15 — Backup plan

Back up daily:

/opt/stacks/sip-asterisk/docker-compose.yml

/opt/stacks/sip-asterisk/Dockerfile

/opt/stacks/sip-asterisk/etc/

/opt/stacks/sip-asterisk/logs/

/opt/stacks/sip-asterisk/recordings/ if call recording is used

/root/pre-sip-backup/

NPM data folder

Firewall rules

Example backup command:

tar \-czf /opt/stacks/sip-asterisk/backup/sip-asterisk-$(date \+%F).tar.gz \\

  /opt/stacks/sip-asterisk/etc \\

  /opt/stacks/sip-asterisk/docker-compose.yml \\

  /opt/stacks/sip-asterisk/Dockerfile

Copy backups off-server:

rsync \-avz /opt/stacks/sip-asterisk/backup/ user@backup-server:/backups/sip-asterisk/

---

# 19\. Stage 16 — Monitoring plan

Minimum monitoring:

\- Container running status

\- Disk usage

\- CPU/RAM

\- Asterisk process health

\- SIP OPTIONS reachability

\- Failed call percentage

\- Concurrent calls

\- RTP packet loss/jitter if available

\- Provider account balance

\- Fail2ban bans

\- SSH login attempts

Useful commands:

docker stats sip-asterisk

docker logs \--tail=200 sip-asterisk

docker exec \-it sip-asterisk asterisk \-rx "core show channels"

docker exec \-it sip-asterisk asterisk \-rx "pjsip show endpoints"

df \-h

free \-h

fail2ban-client status

---

# 20\. Stage 17 — Rollback plan

Before deployment:

\- VPS snapshot taken.

\- Current Docker/NPM state exported.

\- Firewall rules backed up.

\- DNS current state noted.

Rollback commands:

cd /opt/stacks/sip-asterisk

docker compose down

ufw status numbered

Remove SIP-specific firewall rules if needed:

ufw delete allow from PROVIDER\_SIGNALING\_IP to any port 5060 proto udp

ufw delete allow from PROVIDER\_SIGNALING\_IP to any port 5060 proto tcp

ufw delete allow from PROVIDER\_RTP\_IP to any port 10000:20000 proto udp

If the VPS becomes unreachable, use the hosting provider console to restore the snapshot or disable the firewall.

---

# 21\. Final implementation order

Use this exact order:

1\. Confirm provider requirements.

2\. Find and test SSH key locally.

3\. Log in to 185.252.233.186 as root.

4\. Take VPS snapshot.

5\. Backup Docker/NPM/firewall/ports.

6\. Confirm sip.polytronx.com A record points to 185.252.233.186.

7\. Confirm ports 5060/5061 and 10000-20000 do not conflict.

8\. Create /opt/stacks/sip-asterisk.

9\. Add Dockerfile and docker-compose.yml.

10\. Add pjsip.conf, rtp.conf, extensions.conf.

11\. Configure firewall with admin IP and provider IPs only.

12\. Start Asterisk container.

13\. Verify Asterisk transport, endpoint, RTP range.

14\. Ask SIP provider to whitelist 185.252.233.186.

15\. Run SIP OPTIONS / provider reachability test.

16\. Make first outbound test call.

17\. Confirm two-way audio.

18\. Confirm authorized CLI display.

19\. Confirm provider CDR and Asterisk logs.

20\. Add monitoring and backups.

21\. Lock down SSH/NPM/admin access.

22\. Document final config and provider details.

---

# 22\. What must not be done

Do not expose SIP 5060 to the whole internet unless absolutely necessary.

Do not expose RTP 10000-20000 to the whole internet if provider RTP IPs are known.

Do not expose Asterisk AMI 5038 publicly.

Do not paste private SSH keys into chat or tickets.

Do not install native FreePBX on the shared Docker/NPM host without snapshot and conflict review.

Do not send caller IDs that are not approved by your provider.

Do not enable international/premium routes until fraud controls are active.

---

# 23\. Best final recommendation

For your current VPS with many existing Docker/NPM projects:

Production choice:

Asterisk 22 in Docker Compose, host networking, direct SIP/RTP firewall rules.

NPM role:

HTTPS/admin web only, not RTP/SIP media.

Provider role:

Whitelist 185.252.233.186 and approve exact caller IDs.

Security role:

Provider IP whitelist, Fail2ban, no anonymous SIP, no public admin services, route limits, backups, monitoring.

This is the safest path because it keeps the VoIP stack isolated from your existing projects while still allowing the SIP trunk provider to whitelist your single public IP `185.252.233.186`.  
