#!/usr/bin/env bash
# Outbound WARP with LAN/Tailscale/Docker excludes
set -euo pipefail

PW=9450
dsudo() { echo "$PW" | sudo -S "$@"; }

PUBLIC_IP=$(curl -s --max-time 8 ifconfig.me || true)
LAN_IP=$(ip -4 -o addr show enp0s25 | awk '{print $4}' | cut -d/ -f1)
IFACE=enp0s25

log() { printf '[homelab-warp] %s\n' "$*"; }

log "Public IP: ${PUBLIC_IP:-unknown}"
log "LAN IP: ${LAN_IP:-unknown}"

# --- Install cloudflare-warp if missing ---
if ! command -v warp-cli >/dev/null 2>&1; then
  log "Installing cloudflare-warp..."
  curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg -o /tmp/cloudflare-warp.gpg
  dsudo gpg --batch --yes --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg /tmp/cloudflare-warp.gpg
  # noble repo works on Ubuntu 26.04 resolute
  echo 'deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com noble main' | dsudo tee /etc/apt/sources.list.d/cloudflare-client.list >/dev/null
  dsudo apt-get update -qq
  dsudo apt-get install -y cloudflare-warp
fi

warp-cli --version || true

WARP="warp-cli --accept-tos"

# --- Register (idempotent) ---
if ! $WARP registration show 2>/dev/null | grep -qi "Account type\|Device ID\|ID:"; then
  log "Registering WARP..."
  $WARP registration new || true
fi

# --- Split tunnel excludes BEFORE connect (preserve inbound + LAN + Tailscale + Docker) ---
log "Configuring split-tunnel excludes..."

add_exclude() {
  local target=$1
  [[ -z "$target" ]] && return 0
  if $WARP tunnel ip list 2>/dev/null | grep -qF "$target"; then
    log "  already excluded: $target"
  else
    if $WARP tunnel ip add "$target" 2>/dev/null; then
      log "  excluded: $target"
    elif $WARP tunnel ip add-range "$target" 2>/dev/null; then
      log "  excluded range: $target"
    else
      log "  WARN: could not exclude $target"
    fi
  fi
}

# Server own addresses (critical for inbound SSH, Caddy, Minecraft)
add_exclude "$PUBLIC_IP"
add_exclude "$LAN_IP"
add_exclude "192.168.1.0/24"
add_exclude "192.168.1.1"

# Tailscale
add_exclude "100.64.0.0/10"
add_exclude "100.100.100.100"
add_exclude "100.112.109.117"

# Docker bridge ranges on this host
for cidr in 172.17.0.0/16 172.18.0.0/16 172.19.0.0/16 172.20.0.0/16 172.21.0.0/16; do
  add_exclude "$cidr"
done

# RFC1918 / link-local (defaults may cover; explicit is safe)
add_exclude "10.0.0.0/8"
add_exclude "127.0.0.0/8"

# --- Mode: tunnel_only — encrypts outbound WITHOUT binding :53 (AdGuard owns DNS) ---
log "Setting mode tunnel_only (WARP tunnel, AdGuard keeps port 53)..."
$WARP mode tunnel_only 2>/dev/null || true

# --- Connect ---
log "Connecting WARP..."
$WARP connect
sleep 3
$WARP status

# --- Post-connect verification ---
log "Running service checks..."
FAIL=0

check() {
  local name=$1
  shift
  if "$@" >/dev/null 2>&1; then
    log "  OK: $name"
  else
    log "  FAIL: $name"
    FAIL=$((FAIL + 1))
  fi
}

check "AdGuard DNS" dig @127.0.0.1 cloudflare.com +time=2 +tries=1 +short
check "Homepage :3001" curl -sf --max-time 5 -o /dev/null -w '' http://127.0.0.1:3001/
check "Uptime Kuma :3002" curl -sf --max-time 5 -o /dev/null -w '' http://127.0.0.1:3002/
check "Tailscale" tailscale status
check "Docker" docker ps
check "Caddy :443 listen" bash -c 'ss -tln | grep -q ":443 "'

OUT_IP=$(curl -s --max-time 8 https://1.1.1.1/cdn-cgi/trace | grep -E '^warp=|^ip=' || true)
log "Outbound trace: $OUT_IP"

if echo "$OUT_IP" | grep -q 'warp=on'; then
  log "Outbound WARP: ON"
else
  log "WARN: outbound WARP may not be active"
  FAIL=$((FAIL + 1))
fi

# Enable on boot
dsudo systemctl enable warp-svc 2>/dev/null || dsudo systemctl enable cloudflare-warp 2>/dev/null || true

if [[ $FAIL -gt 0 ]]; then
  log "ERRORS: $FAIL checks failed — run rollback if services broken:"
  log "  sudo warp-cli disconnect"
  exit 1
fi

log "Homelab outbound WARP setup complete."
log "Audit: /opt/stacks/privacy/HOMELAB-WARP-AUDIT.md"
