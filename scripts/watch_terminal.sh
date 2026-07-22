#!/usr/bin/env bash
# Cron: keep terminal tunnel healthy + republish URL when it dies
set -euo pipefail

LOG=/var/log/watch_terminal.log
LOCK=/tmp/watch_terminal.lock
mkdir -p "$(dirname "$LOG")"
exec >>"$LOG" 2>&1

if ! mkdir "$LOCK" 2>/dev/null; then
  # stale lock > 10 minutes → clear
  if [ -d "$LOCK" ] && [ $(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) )) -gt 600 ]; then
    rmdir "$LOCK" 2>/dev/null || rm -rf "$LOCK"
    mkdir "$LOCK" || exit 0
  else
    echo "$(date -u +%FT%TZ) skip — already running"
    exit 0
  fi
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

echo "=== $(date -u +%FT%TZ) watch_terminal ==="

run() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  else sudo "$@"; fi
}

# Keep audit log writable by container UID
run chown -R 10001:10001 /opt/stacks/terminal-gateway/data 2>/dev/null || true
run chmod 775 /opt/stacks/terminal-gateway/data 2>/dev/null || true
run chmod 664 /opt/stacks/terminal-gateway/data/audit.log 2>/dev/null || true

# Ensure containers are up (boot keep-alive)
run docker start terminal-gateway >/dev/null 2>&1 || true
run docker start cloudflared-terminal >/dev/null 2>&1 || true

WS_FILE=/opt/stacks/terminal-gateway/data/ws_url.txt
WS=""
[ -f "$WS_FILE" ] && WS=$(run cat "$WS_FILE" 2>/dev/null | head -1 || true)

health_check() {
  local url=$1
  [ -z "$url" ] && return 1
  local http_url="${url/wss:/https:}"
  local code
  code=$(curl -4 -s -o /dev/null -w '%{http_code}' --max-time 10 "$http_url" 2>/dev/null || echo "000")
  case "$code" in
    426|400|404|200) return 0 ;;
    *) echo "health fail: $http_url -> $code"; return 1 ;;
  esac
}

# Also verify Pages still points at a live URL
PAGES_WS=$(curl -4 -s --max-time 10 https://christopher-lab.pages.dev/ws-config.json 2>/dev/null | grep -oE 'wss://[^"]+' | head -1 || true)

if health_check "$WS" && [ -n "$PAGES_WS" ] && [ "$PAGES_WS" = "$WS" ] && health_check "$PAGES_WS"; then
  echo "OK: $WS (pages in sync)"
  exit 0
fi

echo "UNHEALTHY or out of sync (local=$WS pages=$PAGES_WS) — syncing"
/opt/stacks/sync_terminal_ws.sh || {
  echo "sync failed — restarting containers"
  run docker restart terminal-gateway cloudflared-terminal 2>/dev/null || true
  sleep 15
  /opt/stacks/sync_terminal_ws.sh || echo "sync failed after restart"
}