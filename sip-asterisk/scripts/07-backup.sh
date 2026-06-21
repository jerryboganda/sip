#!/usr/bin/env bash
# =============================================================================
# 07-backup.sh — archive the stack config (templates, compose, scripts, etc).
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"
mkdir -p backup
TS="$(date +%F_%H%M)"
TARBALL="backup/sip-asterisk-${TS}.tar.gz"

paths=(config-templates docker-compose.yml Dockerfile docker-entrypoint.sh \
       scripts fail2ban docs .env.example .gitattributes .gitignore)
[ -d etc ]  && paths+=(etc)
[ -f .env ] && paths+=(.env)

tar -czf "$TARBALL" "${paths[@]}"
echo "Created ${TARBALL}"
echo
echo "Copy backups off-server, e.g.:"
echo "  rsync -avz backup/ user@backup-server:/backups/sip-asterisk/"
