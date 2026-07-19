#!/usr/bin/env bash
# Boot: start Docker compose stacks
set -u
LOG=/var/log/homelab-autostart.log
exec >>"$LOG" 2>&1
echo "=== $(date -Is) homelab-autostart starting ==="

# Wait for the Docker daemon to be ready (max ~60s)
for i in $(seq 1 30); do
  if docker info >/dev/null 2>&1; then
    echo "docker ready (after $((i-1)) checks)"
    break
  fi
  echo "waiting for docker ($i)..."
  sleep 2
done

up() {
  local dir="$1"; shift
  if [ -f "$dir/docker-compose.yml" ]; then
    echo "--- bringing up: $dir $* ---"
    ( cd "$dir" && docker compose "$@" up -d ) 2>&1
  else
    echo "!! missing compose file in $dir - skipped"
  fi
}

up /opt/stacks                                          # adguard, homepage
up /opt/stacks/proxy                                    # caddy (reverse proxy / TLS)
up /opt/stacks/searxng                                  # searxng
up /opt/stacks/terminal-gateway                         # terminal-gateway (read-only public shell)
# cloudflared-terminal: start existing container
# recreating rotates the trycloudflare URL
echo "--- starting cloudflared-terminal (no recreate) ---"
docker start cloudflared-terminal 2>&1 || echo "cloudflared-terminal not present yet"
up /opt/visitor-intel                                   # visitor-intel + cloudflared-ingest
# gluetun not started

echo "--- final container state ---"
docker ps --format '{{.Names}}: {{.Status}}'
echo "=== $(date -Is) homelab-autostart done ==="

# lite
cd /opt/stacks/lite && docker compose up -d

# paperless
cd /opt/stacks/paperless && docker compose up -d

cd /opt/stacks/maintenant && docker compose up -d

# crowdsec
cd /opt/stacks/opencanary && docker compose up -d

cd /opt/stacks/crowdsec && docker compose up -d

# nextcloud
cd /opt/stacks/nextcloud && docker compose --env-file /opt/stacks/.expand.secrets up -d

# wazuh
cd /opt/stacks/wazuh/single-node && docker compose up -d
