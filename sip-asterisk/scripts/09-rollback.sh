#!/usr/bin/env bash
# =============================================================================
# 09-rollback.sh — stop the SIP stack and show how to revert firewall changes.
# Confirms before stopping. Does NOT auto-delete firewall rules (manual review).
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

echo "This STOPS the SIP stack (docker compose down)."
read -r -p "Type DOWN to proceed: " a
[ "$a" = "DOWN" ] || { echo "Aborted."; exit 1; }

docker compose down
echo
echo "Stack stopped."
echo
echo "To remove SIP-specific firewall rules, review and delete by number:"
echo "  ufw status numbered"
echo "  ufw delete <num>      # repeat for each 5060 / 10000:20000 rule"
echo
echo "If the VPS is unreachable, restore the snapshot from your hosting panel,"
echo "or temporarily disable the firewall from the provider console: ufw disable"
