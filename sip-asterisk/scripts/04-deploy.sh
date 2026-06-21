#!/usr/bin/env bash
# =============================================================================
# 04-deploy.sh — render config, pull image, and start the SIP stack. RUN ON THE VPS.
# Location: /opt/stacks/sip-asterisk
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

if [ ! -f .env ]; then
    echo "ERROR: .env missing. Copy .env.example to .env and fill in provider values." >&2
    exit 1
fi

echo "== Rendering Asterisk configs =="
bash scripts/render-config.sh

echo "== Ensuring runtime directories =="
mkdir -p etc logs backup
# Asterisk runs as uid 1000 (asterisk) inside the image; make logs writable.
chown -R 1000:1000 logs 2>/dev/null || true

echo "== Pulling Asterisk image =="
docker compose pull

echo "== Starting stack =="
docker compose up -d

echo "== Status =="
docker compose ps
echo
echo "Follow logs with:   docker logs -f sip-asterisk"
echo "Verify SIP with:    bash scripts/05-verify-asterisk.sh"
