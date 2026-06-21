#!/usr/bin/env bash
# =============================================================================
# 01-preflight-audit.sh — RUN ON THE VPS (as root). Read-only audit + backups.
# Saves the pre-change state to /root/pre-sip-backup. Take a provider snapshot
# AFTER this and BEFORE any firewall/port changes.
# =============================================================================
set -uo pipefail
BK=/root/pre-sip-backup
mkdir -p "$BK"

echo "== Host =="
hostnamectl; cat /etc/os-release; date; uptime; whoami
echo
echo "== Network =="
ip addr; ip route
echo
echo "== Disk / Memory =="
df -h; free -h
echo
echo "== Docker =="
docker version; docker compose version; docker info 2>/dev/null | sed -n '1,40p'
echo
echo "== Running containers =="
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}"
docker network ls
docker volume ls
echo
echo "== Ports currently in use =="
ss -tulpn
echo
echo "== SIP-relevant ports (must be free) =="
ss -tulpn | grep -E ':80|:443|:81|:22|:5060|:5061|:10000|:20000' || echo "(none of those bound)"
echo
echo "== Saving pre-change backups to ${BK} =="
docker ps                 > "$BK/docker-ps.txt"
docker network ls         > "$BK/docker-networks.txt"
docker volume ls          > "$BK/docker-volumes.txt"
ss -tulpn                 > "$BK/ports-before.txt"
iptables-save             > "$BK/iptables-before.rules" 2>/dev/null || true
nft list ruleset          > "$BK/nft-before.rules"      2>/dev/null || true
command -v ufw >/dev/null && ufw status verbose > "$BK/ufw-before.txt" 2>/dev/null || true

echo
echo "Done. NOW take a VPS provider snapshot before changing firewall/ports."
