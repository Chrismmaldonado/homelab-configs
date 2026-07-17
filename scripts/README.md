# scripts

Homelab automation for the live portfolio and day-to-day operation.

## fetch_status.py

Runs on the homelab host (cron, every minute):

1. Pulls Uptime Kuma public status page (`homelab` slug)
2. Reads host CPU, RAM, disk from `/proc` (same machine Beszel monitors)
3. Merges deploy timestamp and incident note from local JSON files
4. Queries the Minecraft server for live player count
5. Writes `/opt/stacks/site/status.json`

## sync_site.sh

1. Runs `fetch_status.py`
2. Deploys to Cloudflare Pages when monitor state changes **or** every 10 minutes (so metrics refresh without spamming deploys)

## autostart-all.sh

Boot-time bring-up of every stack in dependency order (DNS → proxy → apps →
security → SIEM). Installed as a systemd unit that runs after `docker.service`.
The cloudflared quick tunnel is started without recreating it so its public
URL doesn't rotate.

## restic-backup.sh

Nightly encrypted backup to a USB stick: stack configs, AdGuard config, cron,
and a fresh Nextcloud Postgres dump. Retention is 7 daily / 4 weekly / 2
monthly. The repo password is stored in a root-only file outside this repo.

## status-pages/refresh.sh

Generates small static HTML status pages for services with no web UI (Caddy
and CrowdSec). Caddy serves them read-only over TLS so the dashboard tiles
have somewhere useful to link.

---

Adjust paths and sudo usage for your environment. **Do not** commit
credentials; use host-local env files (`.env`, `.secrets`, `.cf.env`) kept
outside deployed/site directories. All secrets in this repo are `${...}`
placeholders.
