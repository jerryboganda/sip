#!/usr/bin/env bash
# =============================================================================
# 03-firewall-setup.sh — UFW rules for the SIP host. RUN ON THE VPS (as root).
#
# SAFE BY DEFAULT: prints the plan (dry-run). Re-run with --apply to enable.
#   ./03-firewall-setup.sh            # dry-run, shows rules
#   ./03-firewall-setup.sh --apply    # applies rules + enables UFW
#
# WARNING: SSH (22) is restricted to ADMIN_IP. Make sure ADMIN_IP is your
# current public IP or you can lock yourself out. Keep a console/snapshot ready.
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$HERE/.env}"
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }

APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

: "${ADMIN_IP:?Set ADMIN_IP in .env}"
: "${SIP_PORT:=5060}"
: "${RTP_START:=10000}"
: "${RTP_END:=20000}"
: "${PROVIDER_SIGNALING_IPS:?Set PROVIDER_SIGNALING_IPS in .env (space-separated)}"
: "${PROVIDER_RTP_IPS:?Set PROVIDER_RTP_IPS in .env (space-separated)}"

for v in ADMIN_IP PROVIDER_SIGNALING_IPS PROVIDER_RTP_IPS; do
    case "${!v}" in
        *CHANGE_ME*) echo "ERROR: $v still contains CHANGE_ME. Edit .env." >&2; exit 1;;
    esac
done

rules=()
rules+=("ufw default deny incoming")
rules+=("ufw default allow outgoing")
rules+=("ufw allow from ${ADMIN_IP} to any port 22 proto tcp")
rules+=("ufw allow 80/tcp")
rules+=("ufw allow 443/tcp")
rules+=("ufw allow from ${ADMIN_IP} to any port 81 proto tcp")
for ip in ${PROVIDER_SIGNALING_IPS}; do
    rules+=("ufw allow from ${ip} to any port ${SIP_PORT} proto udp")
    rules+=("ufw allow from ${ip} to any port ${SIP_PORT} proto tcp")
done
for ip in ${PROVIDER_RTP_IPS}; do
    rules+=("ufw allow from ${ip} to any port ${RTP_START}:${RTP_END} proto udp")
done

echo "Planned UFW rules:"
printf '  %s\n' "${rules[@]}"
echo
echo "SSH (22) will be allowed ONLY from ADMIN_IP=${ADMIN_IP}."

if [ "$APPLY" -ne 1 ]; then
    echo
    echo "Dry-run only. Re-run with:  $0 --apply"
    exit 0
fi

read -r -p "Type APPLY to apply these rules and enable UFW: " ans
[ "$ans" = "APPLY" ] || { echo "Aborted."; exit 1; }

for r in "${rules[@]}"; do echo "+ $r"; eval "$r"; done
echo "Enabling UFW..."
ufw --force enable
ufw status verbose
echo
echo "Reminder: Docker can bypass UFW for published ports. This stack uses host"
echo "networking, so also use your hosting provider's external firewall if available."
