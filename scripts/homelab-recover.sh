#!/bin/bash
# Recover Docker stacks, Minecraft, playit after boot/outage
set -euo pipefail

LOG=/var/log/homelab-recover.log
STATE_DIR=/var/lib/homelab-recover
INTERNET_STATE="$STATE_DIR/internet_up"
mkdir -p "$STATE_DIR"

log() { echo "$(date -Is) $*" | tee -a "$LOG"; }

log "=== homelab-recover start ==="

# Core services
for svc in docker minecraft playit; do
  if ! systemctl is-active --quiet "$svc"; then
    log "starting $svc"
    systemctl start "$svc" || log "WARN: failed to start $svc"
  fi
done

# Wait for docker socket
for i in $(seq 1 30); do
  docker info >/dev/null 2>&1 && break
  sleep 2
done

compose_up() {
  local dir="$1"
  local extra="${2:-}"
  if [ -f "$dir/docker-compose.yml" ]; then
    log "compose up: $dir"
    (cd "$dir" && eval "$extra docker compose up -d") || log "WARN: compose failed $dir"
  fi
}

compose_up /opt/stacks/proxy
compose_up /opt/stacks
compose_up /opt/stacks/searxng
compose_up /opt/visitor-intel
compose_up /opt/stacks/terminal-gateway "COMPOSE_PROFILES=quick-tunnel"

# Fix adguard if port 53 conflict caused restart loop
if docker ps -a --format '{{.Names}} {{.Status}}' | grep -q '^adguard Restarting'; then
  log "adguard restarting — ensuring DNSStubListener=no"
  mkdir -p /etc/systemd/resolved.conf.d
  if [ ! -f /etc/systemd/resolved.conf.d/adguard.conf ]; then
    printf '[Resolve]\nDNSStubListener=no\n' > /etc/systemd/resolved.conf.d/adguard.conf
    systemctl restart systemd-resolved || true
  fi
  docker restart adguard || true
fi

# Internet restore detection
WAS_UP=0
[ -f "$INTERNET_STATE" ] && WAS_UP=$(cat "$INTERNET_STATE" || echo 0)

NOW_UP=0
if ping -c1 -W4 1.1.1.1 >/dev/null 2>&1 || ping -c1 -W4 8.8.8.8 >/dev/null 2>&1; then
  NOW_UP=1
fi

if [ "$NOW_UP" -eq 1 ] && [ "$WAS_UP" -eq 0 ]; then
  log "INTERNET RESTORED — bouncing tunnel services"
  systemctl restart playit || true
  for c in cloudflared-terminal cloudflared-ingest; do
    docker restart "$c" 2>/dev/null || true
  done
  docker restart caddy 2>/dev/null || true
fi

echo "$NOW_UP" > "$INTERNET_STATE"

RUNNING=$(docker ps -q | wc -l)
log "containers running: $RUNNING"
log "=== homelab-recover done ==="
