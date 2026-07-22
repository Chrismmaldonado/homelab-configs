#!/usr/bin/env bash
# Sync terminal WS URL from cloudflared quick tunnel to Pages
set -euo pipefail

SITE=/opt/stacks/site
ENVFILE=/opt/stacks/.cf.env
PROJECT=christopher-lab
DATA=/opt/stacks/terminal-gateway/data
WS_FILE="$DATA/ws_url.txt"
CONTAINER=cloudflared-terminal
GATEWAY=terminal-gateway

log() { printf '[sync_terminal_ws] %s\n' "$*"; }

run() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

extract_tunnel_url() {
  # Prefer the URL from the most recent "quick Tunnel has been created" banner
  run docker logs "$CONTAINER" 2>&1 | awk '
    /Your quick Tunnel has been created/ { grab=1; next }
    grab && match($0, /https:\/\/[a-z0-9-]+\.trycloudflare\.com/, m) { url=m[0]; grab=0 }
    END { if (url) print url }
  '
}

health_check() {
  local ws_url=$1
  local http_url="${ws_url/wss:/https:}"
  local code try=0
  while [ "$try" -lt 8 ]; do
    code=$(curl -4 -s -o /dev/null -w '%{http_code}' --max-time 12 "$http_url" 2>/dev/null || echo "000")
    case "$code" in
      426|400|404|200) return 0 ;;
      530|502|000) try=$((try + 1)); sleep 3 ;;
      *) log "health HTTP $http_url -> $code"; try=$((try + 1)); sleep 3 ;;
    esac
  done
  log "health HTTP $http_url -> $code (after retries)"
  return 1
}

ensure_containers() {
  run docker start "$GATEWAY" >/dev/null 2>&1 || true
  if ! run docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    log "Starting $CONTAINER..."
    # Prefer existing container; if missing recreate quick-tunnel profile
    if run docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
      run docker start "$CONTAINER"
    else
      ( cd /opt/stacks/terminal-gateway && run docker compose --profile quick-tunnel up -d cloudflared-quick )
    fi
    sleep 10
  fi
}

restart_tunnel() {
  log "Restarting $CONTAINER (mint new trycloudflare URL)..."
  run docker restart "$CONTAINER"
  sleep 14
}

ensure_containers

URL=$(extract_tunnel_url | tail -1 || true)
WS=""
[ -n "${URL:-}" ] && WS="${URL/https/wss}"

NEED_RESTART=0
if [ -z "$WS" ]; then
  NEED_RESTART=1
elif ! health_check "$WS"; then
  NEED_RESTART=1
fi

if [ "$NEED_RESTART" -eq 1 ]; then
  restart_tunnel
  URL=$(extract_tunnel_url | tail -1 || true)
  [ -z "${URL:-}" ] && { log "ERROR: no tunnel URL after restart"; exit 1; }
  WS="${URL/https/wss}"
  if ! health_check "$WS"; then
    log "ERROR: WSS still failing after restart: $WS"
    exit 1
  fi
fi

UPDATED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
log "Live WSS: $WS"

OLD=""
[ -f "$SITE/ws-config.json" ] && OLD=$(run cat "$SITE/ws-config.json" 2>/dev/null | grep -oE 'wss://[^"]+' | head -1 || true)

TMP=$(mktemp)
cat > "$TMP" <<EOF
{"url":"$WS","fallbacks":["wss://terminal.christopher-lab.pages.dev"],"updatedAt":"$UPDATED"}
EOF
run cp "$TMP" "$SITE/ws-config.json"
run mkdir -p "$DATA"
printf '%s\n' "$WS" > "$TMP"
run cp "$TMP" "$WS_FILE"
rm -f "$TMP"
run chown -R 10001:10001 "$DATA" 2>/dev/null || true

if [ -f "$ENVFILE" ]; then
  log "Updating Pages WS_URL secret..."
  run docker run --rm --cpus=0.5 --memory=1536m --cpu-shares=128 --blkio-weight=50 \
    -e npm_config_cache=/root/.npm -v /opt/stacks/.wrangler-cache:/root/.npm \
    --env-file "$ENVFILE" node:22-alpine \
    sh -c "printf '%s' '$WS' | npx -y wrangler@latest pages secret put WS_URL --project-name=$PROJECT" 2>&1 | tail -5 || true
  run docker run --rm --cpus=0.5 --memory=1536m --cpu-shares=128 --blkio-weight=50 \
    -e npm_config_cache=/root/.npm -v /opt/stacks/.wrangler-cache:/root/.npm \
    --env-file "$ENVFILE" node:22-alpine \
    sh -c "printf '%s' '$UPDATED' | npx -y wrangler@latest pages secret put WS_UPDATED_AT --project-name=$PROJECT" 2>&1 | tail -3 || true
fi

log "Deploying Pages with fresh ws-config..."
/opt/stacks/deploy_pages.sh
log "Done. OLD=$OLD NEW=$WS"