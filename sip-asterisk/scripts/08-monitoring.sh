#!/usr/bin/env bash
# =============================================================================
# 08-monitoring.sh — quick health snapshot of the SIP host + Asterisk.
# =============================================================================
set -uo pipefail
C=sip-asterisk

echo "== Container =="
docker ps --filter "name=$C" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo "== Resource usage =="
docker stats --no-stream "$C" 2>/dev/null || true
echo "== Active channels =="
docker exec -i "$C" asterisk -rx "core show channels" 2>/dev/null
echo "== Endpoints / trunk status =="
docker exec -i "$C" asterisk -rx "pjsip show endpoints" 2>/dev/null
docker exec -i "$C" asterisk -rx "pjsip show aors" 2>/dev/null
echo "== Disk =="; df -h /
echo "== Memory =="; free -h
echo "== Fail2ban =="
fail2ban-client status 2>/dev/null || echo "(fail2ban not installed on host)"
fail2ban-client status asterisk-security 2>/dev/null || true
echo "== Recent warnings/errors =="
docker logs --tail=100 "$C" 2>&1 | grep -iE "error|warning|fail|secur" | tail -n 20 || true
