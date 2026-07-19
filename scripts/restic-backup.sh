#!/bin/bash
# Nightly restic backup to USB
set -euo pipefail
export RESTIC_REPOSITORY=/mnt/backup-usb/restic
export RESTIC_PASSWORD_FILE=/opt/stacks/.restic.pass
findmnt /mnt/backup-usb >/dev/null || mount /mnt/backup-usb

STAGE=/mnt/backup-usb/restic-stage
mkdir -p "$STAGE"
# Nextcloud DB dump (best-effort)
if docker ps --format '{{.Names}}' | grep -qx nextcloud-db; then
  docker exec nextcloud-db pg_dump -U nextcloud nextcloud > "$STAGE/nextcloud.sql" || true
fi

restic backup --tag homelab \
  /opt/stacks/proxy/Caddyfile \
  /opt/stacks/adguard/conf \
  /opt/stacks/homepage/config \
  /opt/stacks/*/docker-compose.yml \
  /opt/stacks/wazuh/single-node/docker-compose.override.yml \
  /opt/stacks/autostart-all.sh \
  /opt/stacks/site/wrangler.toml \
  /opt/stacks/site/ws-config.json \
  /etc/cron.d \
  "$STAGE" \
  --exclude='**/.git/**' --exclude='**/node_modules/**'
restic forget --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 2
df -h /mnt/backup-usb
