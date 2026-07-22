#!/usr/bin/env bash
# Daily safe cache purge — does not touch worlds, compose data volumes, or in-use images
set -u
LOG=/var/log/homelab-cache-purge.log
exec >>"$LOG" 2>&1
echo "=== $(date -Is) cache-purge start ==="
BEFORE=$(df -P / | awk 'NR==2{print $3}')

# Docker build cache + dangling images only (never prune -a)
if command -v docker >/dev/null; then
  docker builder prune -af 2>/dev/null || true
  docker image prune -f 2>/dev/null || true
fi

# App/tool caches
rm -rf /opt/stacks/.wrangler-cache 2>/dev/null || true
rm -rf /root/.npm /home/homelab2/.npm /tmp/npm-* 2>/dev/null || true
rm -rf /var/tmp/npm-* /tmp/wrangler* 2>/dev/null || true

# Apt lists/archives
apt-get clean >/dev/null 2>&1 || true

# Journals (keep 7 days)
journalctl --vacuum-time=7d >/dev/null 2>&1 || true

# Old temp files
find /tmp -xdev -type f -mtime +3 -delete 2>/dev/null || true
find /var/tmp -xdev -type f -mtime +7 -delete 2>/dev/null || true

# Minecraft rotated logs older than 14d (keep latest.log)
find /opt/minecraft/server/logs -type f -name '*.log.gz' -mtime +14 -delete 2>/dev/null || true

AFTER=$(df -P / | awk 'NR==2{print $3}')
echo "disk KB before=$BEFORE after=$AFTER freed_kb=$((BEFORE-AFTER))"
echo "=== $(date -Is) cache-purge done ==="
