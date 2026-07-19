#!/usr/bin/env bash
# Sync terminal WS URL from cloudflared to Pages
set -euo pipefail
PW=9450
dsudo() { echo "$PW" | sudo -S "$@"; }

SITE=/opt/stacks/site
ENVFILE=/opt/stacks/.cf.env
PROJECT=christopher-lab
DATA=/opt/stacks/terminal-gateway/data
WS_FILE="$DATA/ws_url.txt"
CONTAINER=cloudflared-terminal
GATEWAY=terminal-gateway

log() { printf '[sync_terminal_ws] %s\n' "$*"; }

extract_tunnel_url() {
  local url
  url=$(dsudo docker logs "$CONTAINER" 2>&1 | grep -A1 'Your quick Tunnel has been created' | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1)
  if [ -n "$url" ]; then
    echo "$url"
    return
  fi
  dsudo docker logs "$CONTAINER" 2>&1 | tail -500 | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1
}

health_check() {
  local ws_url=$1
  local http_url="${ws_url/wss:/https:}"
  local code try=0
  # 426 = WS upgrade required (tunnel + origin up)
  while [ "$try" -lt 6 ]; do
    code=$(curl -4 -s -o /dev/null -w '%{http_code}' --max-time 12 "$http_url" 2>/dev/null || echo "000")
    case "$code" in
      426|400|404|200) return 0 ;;
      530|502|000) try=$((try + 1)); sleep 5 ;;
      *) log "health HTTP $http_url -> $code"; return 1 ;;
    esac
  done
  log "health HTTP $http_url -> $code (after retries)"
  return 1
}

ensure_tunnel() {
  if ! dsudo docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    log "Starting $CONTAINER..."
    dsudo docker start "$CONTAINER" 2>/dev/null || true
    sleep 8
  fi
  if ! dsudo docker ps --format '{{.Names}}' | grep -qx "$GATEWAY"; then
    log "Starting $GATEWAY..."
    dsudo docker start "$GATEWAY" 2>/dev/null || true
    sleep 3
  fi
}

restart_tunnel() {
  log "Restarting $CONTAINER..."
  dsudo docker restart "$CONTAINER"
  sleep 12
}

ensure_tunnel

URL=$(extract_tunnel_url | tail -1)
if [ -z "$URL" ]; then
  log "No tunnel URL in logs — restarting cloudflared"
  restart_tunnel
  URL=$(extract_tunnel_url | tail -1)
fi

if [ -z "$URL" ]; then
  log "ERROR: still no tunnel URL"
  exit 1
fi

WS="${URL/https/wss}"
UPDATED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Health check current URL
if ! health_check "$WS"; then
  log "WSS health check failed for $WS — restarting tunnel"
  restart_tunnel
  URL=$(extract_tunnel_url | tail -1)
  [ -z "$URL" ] && { log "ERROR: no URL after restart"; exit 1; }
  WS="${URL/https/wss}"
  if ! health_check "$WS"; then
    log "ERROR: WSS still failing after restart"
    exit 1
  fi
fi

log "Live WSS: $WS"

OLD=""
[ -f "$SITE/ws-config.json" ] && OLD=$(dsudo cat "$SITE/ws-config.json" 2>/dev/null | grep -oE 'wss://[^"]+' | head -1 || true)

TMP=$(mktemp)
cat > "$TMP" <<EOF
{"url":"$WS","fallbacks":["wss://terminal.christopher-lab.pages.dev"],"updatedAt":"$UPDATED"}
EOF
dsudo cp "$TMP" "$SITE/ws-config.json"
dsudo mkdir -p "$DATA"
printf '%s\n' "$WS" > "$TMP"
dsudo cp "$TMP" "$WS_FILE"
rm -f "$TMP"

# Pages Function env (WS_URL secret — no full redeploy needed for URL-only updates)
if [ -f "$ENVFILE" ]; then
  log "Updating Pages WS_URL secret..."
  dsudo docker run --rm --cpus=0.5 --memory=1536m --cpu-shares=128 --blkio-weight=50 -e npm_config_cache=/root/.npm -v /opt/stacks/.wrangler-cache:/root/.npm --env-file "$ENVFILE" node:22-alpine \
    sh -c "printf '%s' '$WS' | npx -y wrangler@latest pages secret put WS_URL --project-name=$PROJECT" 2>&1 | tail -3 || true
  dsudo docker run --rm --cpus=0.5 --memory=1536m --cpu-shares=128 --blkio-weight=50 -e npm_config_cache=/root/.npm -v /opt/stacks/.wrangler-cache:/root/.npm --env-file "$ENVFILE" node:22-alpine \
    sh -c "printf '%s' '$UPDATED' | npx -y wrangler@latest pages secret put WS_UPDATED_AT --project-name=$PROJECT" 2>&1 | tail -3 || true
fi

# Full deploy when ws-config changed (static fallback + terminal.js updates)
if [ "$WS" != "$OLD" ] || [ ! -f "$SITE/.deploy.json" ]; then
  log "Deploying Pages (ws-config changed)..."
  /opt/stacks/deploy_pages.sh
else
  log "ws-config unchanged; secret-only update"
fi

log "Done."
