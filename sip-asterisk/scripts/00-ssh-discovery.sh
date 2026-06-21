#!/usr/bin/env bash
# =============================================================================
# 00-ssh-discovery.sh — RUN ON YOUR LOCAL PC (Linux/macOS), read-only.
# Helps you locate the SSH key for the VPS. Never paste private keys anywhere.
# =============================================================================
set -uo pipefail
HOST_IP="185.252.233.186"
HOST_FQDN="sip.polytronx.com"

echo "== SSH keys in ~/.ssh =="
ls -la ~/.ssh 2>/dev/null || echo "(no ~/.ssh directory)"
echo
echo "== Loaded ssh-agent identities =="
ssh-add -l 2>/dev/null || echo "(no identities / agent not running)"
echo
echo "== References to the host in ssh config/keys =="
grep -R "${HOST_IP}\|${HOST_FQDN}" ~/.ssh/config ~/.ssh/* 2>/dev/null || echo "(none found)"
echo
echo "== Candidate private keys =="
for k in ~/.ssh/id_* ~/.ssh/*.pem ~/.ssh/*.key; do
    [ -e "$k" ] || continue
    if ssh-keygen -y -f "$k" >/dev/null 2>&1; then
        echo "Possible SSH private key: $k"
    fi
done
echo
echo "Test the connection with:"
echo "  ssh -o IdentitiesOnly=yes root@${HOST_IP}"
echo "  ssh -i ~/.ssh/YOUR_KEY_FILE -o IdentitiesOnly=yes root@${HOST_IP}"
