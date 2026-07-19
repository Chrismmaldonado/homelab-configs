#!/usr/bin/env bash
# Cron: keep terminal tunnel healthy
set -euo pipefail
PW=9450
dsudo() { echo "$PW" | sudo -S "$@"; }

LOG=/var/log/watch_terminal.log
LOCK=/tmp/watch_terminal.lock

exec >>"$LOG" 2>&1

if ! mkdir "$LOCK" 2>/dev/null; then
  echo "$(date -u +%FT%TZ) skip — already running"
  exit 0
fi
trap 'rmdir "$LOCK"' EXIT

echo "=== $(date -u +%FT%TZ) watch_terminal ==="

# Keep audit log writable by container UID
dsudo chown -R 10001:10001 /opt/stacks/terminal-gateway/data 2>/dev/null || true
dsudo chmod 775 /opt/stacks/terminal-gateway/data 2>/dev/null || true
dsudo chmod 664 /opt/stacks/terminal-gateway/data/audit.log 2>/dev/null || true

WS_FILE=/opt/stacks/terminal-gateway/data/ws_url.txt
WS=""
[ -f "$WS_FILE" ] && WS=$(dsudo cat "$WS_FILE" 2>/dev/null | head -1 || true)

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

if health_check "$WS"; then
  echo "OK: $WS"
  exit 0
fi

echo "UNHEALTHY — running sync_terminal_ws.sh"
/opt/stacks/sync_terminal_ws.sh || {
  echo "sync failed — restarting containers"
  dsudo docker restart terminal-gateway cloudflared-terminal 2>/dev/null || true
  sleep 15
  /opt/stacks/sync_terminal_ws.sh || echo "sync failed after restart"
}