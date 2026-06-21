#!/usr/bin/env bash
# =============================================================================
# Container entrypoint:
#   1. Ensure the asterisk user/group exist.
#   2. Seed empty bind-mounted volumes from baked-in package defaults
#      (so sounds / keys / astdb survive even with empty host directories).
#   3. Fix ownership of runtime dirs, then drop privileges to the asterisk user.
# NOTE: This file MUST use LF line endings (enforced via .gitattributes).
# =============================================================================
set -euo pipefail

# --- 1. asterisk user/group ---------------------------------------------------
if ! getent group asterisk >/dev/null 2>&1; then
    groupadd --system asterisk
fi
if ! id asterisk >/dev/null 2>&1; then
    useradd --system --gid asterisk \
        --home-dir /var/lib/asterisk --shell /usr/sbin/nologin asterisk
fi

# --- 2. seed persistent volumes if empty -------------------------------------
seed_dir() {
    local target="$1" defaults="$2"
    if [ -d "$target" ] && [ -z "$(ls -A "$target" 2>/dev/null || true)" ]; then
        echo "[entrypoint] Seeding ${target} from packaged defaults..."
        cp -a "${defaults}/." "${target}/"
    fi
}
seed_dir /var/lib/asterisk   /opt/asterisk-defaults/var-lib-asterisk
seed_dir /var/spool/asterisk /opt/asterisk-defaults/var-spool-asterisk

# --- 3. ownership + sanity ----------------------------------------------------
mkdir -p /var/log/asterisk /var/spool/asterisk /var/lib/asterisk /var/run/asterisk
chown -R asterisk:asterisk \
    /var/log/asterisk /var/spool/asterisk /var/lib/asterisk /var/run/asterisk || true

if [ ! -f /etc/asterisk/pjsip.conf ]; then
    echo "[entrypoint] WARNING: /etc/asterisk/pjsip.conf missing." >&2
    echo "[entrypoint] Did you run scripts/render-config.sh (or scripts/04-deploy.sh)?" >&2
fi

echo "[entrypoint] Starting: $*"
exec "$@"
