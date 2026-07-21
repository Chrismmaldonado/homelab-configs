#!/usr/bin/env bash
# Boot: start Docker compose stacks (idempotent; safe to re-run)
set -u
LOG=/var/log/homelab-autostart.log
exec >>"$LOG" 2>&1
echo "=== $(date -Is) homelab-autostart starting ==="

# Wait for the Docker daemon to be ready (max ~90s)
for i in $(seq 1 45); do
  if docker info >/dev/null 2>&1; then
    echo "docker ready (after $((i-1)) checks)"
    break
  fi
  echo "waiting for docker ($i)..."
  sleep 2
done

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: docker not ready — aborting stack start"
  exit 1
fi

up() {
  local dir="$1"; shift
  if [ -f "$dir/docker-compose.yml" ]; then
    echo "--- bringing up: $dir $* ---"
    ( cd "$dir" && docker compose "$@" up -d ) 2>&1 || echo "WARN: compose failed in $dir"
    # brief pause so dependent stacks do not stampede the disk/CPU
    sleep 2
  else
    echo "!! missing compose file in $dir - skipped"
  fi
}

# Core edge + DNS/dashboard first
up /opt/stacks                                          # adguard, homepage
up /opt/stacks/proxy                                    # caddy
up /opt/stacks/lite                                     # unbound
up /opt/stacks/ntfy

# Mail
up /opt/stacks/stalwart
up /opt/stacks/roundcube
up /opt/stacks/cloudflared-mail
up /opt/stacks/mail-setup

# Apps
up /opt/stacks/searxng
up /opt/stacks/paperless
up /opt/stacks/nextcloud --env-file /opt/stacks/.expand.secrets
up /opt/stacks/maintenant
up /opt/stacks/opencanary
up /opt/stacks/crowdsec

# Public shell / visitors
up /opt/stacks/terminal-gateway
# cloudflared-terminal: start existing container only (recreate rotates trycloudflare URL)
echo "--- starting cloudflared-terminal (no recreate) ---"
docker start cloudflared-terminal 2>&1 || echo "cloudflared-terminal not present yet"
up /opt/visitor-intel

# SIEM last (heavy)
up /opt/stacks/wazuh/single-node

# Intentionally not started: gluetun

echo "--- final container state ---"
docker ps --format '{{.Names}}: {{.Status}}'
echo "=== $(date -Is) homelab-autostart done ==="
