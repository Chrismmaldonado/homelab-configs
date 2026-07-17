# scripts

Homelab automation for the live portfolio and day-to-day operation.

## fetch_status.py

Runs on the homelab host (cron, every minute):

1. Pulls Maintenant endpoint checks (`GET /api/v1/endpoints`)
2. Reads host CPU, RAM, disk from `/proc`
3. Merges deploy timestamp and incident note from local JSON files
4. Queries the Minecraft server for live player count
5. Writes `/opt/stacks/site/status.json`

## sync_site.sh

1. Runs `fetch_status.py`
2. Deploys to Cloudflare Pages when monitor state changes **or** every 10 minutes

## autostart-all.sh

Boot-time bring-up of every stack in dependency order. Installed as a systemd
unit after `docker.service`. Starts Maintenant (not Kuma/Beszel/Dozzle).

## restic-backup.sh

Nightly encrypted backup to USB: stack configs + Nextcloud Postgres dump.

## status-pages/refresh.sh

Static HTML status pages for Caddy and CrowdSec (services with no admin UI).

---

**Do not** commit credentials. Use host-local env files outside deploy paths.
