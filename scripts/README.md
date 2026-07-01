# scripts

Homelab automation for the live portfolio.

## fetch_status.py

Runs on the homelab host (cron, every minute):

1. Pulls Uptime Kuma public status page (`homelab` slug)
2. Reads host CPU, RAM, disk from `/proc` (same machine Beszel monitors)
3. Merges deploy timestamp and incident note from local JSON files
4. Writes `/opt/stacks/site/status.json`

## sync_site.sh

1. Runs `fetch_status.py`
2. Deploys to Cloudflare Pages when monitor state changes **or** every 10 minutes (so metrics refresh without spamming deploys)

Adjust paths and sudo usage for your environment. **Do not** commit credentials; use host-local env files outside the site directory.
