#!/usr/bin/env bash
# =============================================================================
# 05-verify-asterisk.sh — verify the running Asterisk + PJSIP trunk state.
# =============================================================================
set -uo pipefail
C=sip-asterisk
ax(){ docker exec -i "$C" asterisk -rx "$1"; }

echo "== Transports ==";  ax "pjsip show transports"
echo "== Endpoints ==";   ax "pjsip show endpoints"
echo "== AORs ==";        ax "pjsip show aors"
echo "== Identifies ==";  ax "pjsip show identifies"
echo "== Contacts ==";    ax "pjsip show contacts"
echo "== Channels ==";    ax "core show channels"
echo "== Uptime ==";      ax "core show uptime"
echo
echo "Endpoint detail:"
ax "pjsip show endpoint provider-endpoint"
