#!/usr/bin/env bash
# =============================================================================
# 06-testing-checklist.sh — network + SIP reachability checks and test helpers.
# =============================================================================
set -uo pipefail
DOMAIN="${1:-sip.polytronx.com}"
C=sip-asterisk

echo "== DNS =="
dig +short "$DOMAIN" A

echo "== Listening SIP/RTP ports on host =="
ss -tulpn | grep -E ':5060|:5061|:10000|:20000' || echo "(none bound yet)"

echo "== Recent Asterisk logs =="
docker logs --tail=100 "$C" 2>&1 | tail -n 100

echo "== Endpoint detail =="
docker exec -i "$C" asterisk -rx "pjsip show endpoint provider-endpoint" 2>/dev/null

cat <<'EOF'

------------------------------------------------------------------------------
MANUAL TEST STEPS (in order)
------------------------------------------------------------------------------
1) Live SIP trace:        docker exec -it sip-asterisk sngrep
   PJSIP protocol log on:  docker exec -it sip-asterisk asterisk -rx "pjsip set logger on"
   ...and off again:       docker exec -it sip-asterisk asterisk -rx "pjsip set logger off"

2) Confirm provider reachability (OPTIONS qualify -> AOR should show "Avail").
   bash scripts/05-verify-asterisk.sh   # look at AORs/Contacts status

3) First outbound test call (replace with provider's test/echo number):
   docker exec -it sip-asterisk asterisk -rx \
     "channel originate PJSIP/PROVIDER_TEST_NUMBER@provider-endpoint application Echo"

4) Outbound call to your own mobile (use full number in provider's format),
   verify two-way audio and that the displayed CLI == your AUTHORIZED_CLI.

5) Check provider CDR/portal and local CDR: ./logs/cdr-csv/Master.csv

6) Negative test: try an UNAUTHORIZED CLI and confirm the provider rejects it.
------------------------------------------------------------------------------
COMMON FAILURES
  403 Forbidden          -> IP not whitelisted / CLI not authorized
  401 Unauthorized       -> provider wants registration auth, not IP-auth
  404 / 484              -> wrong dialed-number format
  488 Not Acceptable     -> codec mismatch (check allow=alaw,ulaw)
  one-way / no audio     -> RTP firewall/NAT (check external_media_address + RTP IPs)
------------------------------------------------------------------------------
EOF
