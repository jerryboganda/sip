#!/usr/bin/env bash
# =============================================================================
# 02-dns-validation.sh — confirm sip.polytronx.com points to the VPS.
# Usage: ./02-dns-validation.sh [domain] [expected-ip]
# =============================================================================
set -uo pipefail
DOMAIN="${1:-sip.polytronx.com}"
EXPECT="${2:-185.252.233.186}"

echo "== Local resolver =="; dig +short "$DOMAIN" A
echo "== Cloudflare 1.1.1.1 =="; dig @1.1.1.1 +short "$DOMAIN" A
echo "== Google 8.8.8.8 =="; dig @8.8.8.8 +short "$DOMAIN" A

got="$(dig +short "$DOMAIN" A | tail -n1)"
echo
if [ "$got" = "$EXPECT" ]; then
    echo "OK: ${DOMAIN} -> ${EXPECT}"
else
    echo "WARN: ${DOMAIN} -> '${got}' (expected ${EXPECT}). Fix DNS before provider tests."
    exit 1
fi
