#!/usr/bin/env bash
# =============================================================================
# render-config.sh — generate ./etc/*.conf from ./config-templates/*.conf
# Replaces ONLY __TOKEN__ placeholders using values from .env.
# Asterisk ${VARIABLES} (e.g. ${EXTEN}) are never touched.
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

ENV_FILE="${1:-$HERE/.env}"
if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: env file not found: $ENV_FILE" >&2
    echo "Copy .env.example to .env and fill in your provider values." >&2
    exit 1
fi
# shellcheck disable=SC1090
set -a; . "$ENV_FILE"; set +a

# Required values must be present and non-empty.
REQUIRED=(PUBLIC_IP SIP_DOMAIN SIP_PORT RTP_START RTP_END \
          PROVIDER_GATEWAY_IP PROVIDER_SIGNALING_IP)
missing=()
for k in "${REQUIRED[@]}"; do
    [ -z "${!k:-}" ] && missing+=("$k")
done
if [ "${#missing[@]}" -gt 0 ]; then
    echo "ERROR: missing or empty in ${ENV_FILE}: ${missing[*]}" >&2
    exit 1
fi

mkdir -p etc

# Tokens that templates may contain.
TOKENS=(TZ PUBLIC_IP SIP_DOMAIN SIP_PORT RTP_START RTP_END \
        PROVIDER_GATEWAY_IP PROVIDER_SIGNALING_IP)

shopt -s nullglob
for tpl in config-templates/*.conf; do
    out="etc/$(basename "$tpl")"
    cp "$tpl" "$out"
    for key in "${TOKENS[@]}"; do
        val="${!key:-}"
        esc=$(printf '%s' "$val" | sed -e 's/[\/&]/\\&/g')
        sed -i "s/__${key}__/${esc}/g" "$out"
    done
done

# Guard: no leftover placeholders.
if grep -RnE '__[A-Z0-9_]+__' etc/ ; then
    echo "ERROR: Unresolved __TOKEN__ placeholders remain (see above)." >&2
    echo "Add the missing variable(s) to .env." >&2
    exit 1
fi

# Guard: no unfilled CHANGE_ME values leaked into the config.
if grep -Rq 'CHANGE_ME' etc/ ; then
    echo "ERROR: CHANGE_ME placeholder(s) found in rendered config:" >&2
    grep -Rn 'CHANGE_ME' etc/ >&2 || true
    echo "Edit .env with real provider values, then re-run." >&2
    exit 1
fi

echo "Rendered configs into ./etc :"
ls -1 etc/
