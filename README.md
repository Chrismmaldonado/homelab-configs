# homelab-configs

Sanitized reference configs for my homelab portfolio ([christopher.isageek.net](https://christopher.isageek.net)).

No secrets, tokens, passwords, or private domains with live credentials. Copy and adapt for your own lab.

## What's here

| Path | Purpose |
|------|---------|
| `terminal-gateway/` | Read-only WebSocket shell (path jail, redaction, audit log) |
| `scripts/fetch_status.py` | Pulls Uptime Kuma + host CPU/RAM/disk into `status.json` |
| `scripts/sync_site.sh` | Cron-friendly sync to Cloudflare Pages |
| `caddy/Caddyfile.example` | Reverse proxy + DNS-01 TLS pattern |
| `site/ws-config.example.json` | Cloudflare quick tunnel WebSocket URL template |

## Security notes

- Secrets live **outside** deploy paths (e.g. `/opt/stacks/.cf.env`, not in `site/`).
- Terminal gateway: read-only rootfs, `cap_drop: ALL`, no `.env` / keys in allowed paths.
- Public site on Cloudflare Pages; homelab exposes only outbound tunnels.

## Requirements

- Linux host with Docker
- Cloudflare account (Pages + optional Tunnel)
- Uptime Kuma on localhost for status sync

## License

MIT — use freely, no warranty.
