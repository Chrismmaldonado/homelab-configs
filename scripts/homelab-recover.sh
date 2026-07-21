#!/usr/bin/env bash
# Recover Docker stacks, Minecraft, playit after boot/outage.
# Idempotent watchdog — safe every few minutes. Does not reboot the host.
set -u
set +e

LOG=/var/log/homelab-recover.log
STATE_DIR=/var/lib/homelab-recover
INTERNET_STATE="$STATE_DIR/internet_up"
mkdir -p "$STATE_DIR"

log() { echo "$(date -Is) $*" | tee -a "$LOG"; }

log "=== homelab-recover start ==="

# Core host services
for svc in docker tailscaled wg-quick@wg0 minecraft playit; do
  if systemctl list-unit-files "${svc}.service" &>/dev/null || systemctl cat "${svc}.service" &>/dev/null; then
    if ! systemctl is-active --quiet "$svc"; then
      log "starting $svc"
      systemctl start "$svc" || log "WARN: failed to start $svc"
    fi
  fi
done

# Mail DNAT rules for Tailscale exit-node hairpin (oneshot)
if systemctl cat tailscale-mail-dnat.service &>/dev/null; then
  systemctl start tailscale-mail-dnat.service || log "WARN: tailscale-mail-dnat failed"
fi

# Wait for docker socket (graceful)
for i in $(seq 1 45); do
  docker info >/dev/null 2>&1 && break
  sleep 2
done

if ! docker info >/dev/null 2>&1; then
  log "ERROR: docker not ready"
  exit 1
fi

# Full stack bring-up (compose up -d is no-op when healthy)
if [ -x /opt/stacks/autostart-all.sh ]; then
  log "running autostart-all.sh"
  /opt/stacks/autostart-all.sh || log "WARN: autostart-all returned non-zero"
else
  log "WARN: /opt/stacks/autostart-all.sh missing"
fi

# AdGuard DNSStubListener conflict recovery
if docker ps -a --format '{{.Names}} {{.Status}}' | grep -q '^adguard Restarting'; then
  log "adguard restarting — ensuring DNSStubListener=no"
  mkdir -p /etc/systemd/resolved.conf.d
  if [ ! -f /etc/systemd/resolved.conf.d/adguard.conf ]; then
    printf '[Resolve]\nDNSStubListener=no\n' > /etc/systemd/resolved.conf.d/adguard.conf
    systemctl restart systemd-resolved || true
  fi
  docker restart adguard || true
fi

# Internet restore → bounce outbound tunnels
WAS_UP=0
[ -f "$INTERNET_STATE" ] && WAS_UP=$(cat "$INTERNET_STATE" || echo 0)

NOW_UP=0
if ping -c1 -W4 1.1.1.1 >/dev/null 2>&1 || ping -c1 -W4 8.8.8.8 >/dev/null 2>&1; then
  NOW_UP=1
fi

if [ "$NOW_UP" -eq 1 ] && [ "$WAS_UP" -eq 0 ]; then
  log "INTERNET RESTORED — bouncing tunnel services"
  systemctl restart playit || true
  for c in cloudflared-terminal cloudflared-ingest cloudflared-mail; do
    docker restart "$c" 2>/dev/null || true
  done
  docker restart caddy 2>/dev/null || true
fi

echo "$NOW_UP" > "$INTERNET_STATE"

RUNNING=$(docker ps -q | wc -l)
EXPECTED=$(docker ps -aq | wc -l)
log "containers running: $RUNNING / $EXPECTED listed"
log "=== homelab-recover done ==="
exit 0
