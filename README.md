# homelab-configs

Sanitized configs for the homelab behind [christopher.isageek.net](https://christopher.isageek.net).

No secrets, tokens, or live credentials. Domains appear as examples where needed.

## Layout

| Path | Contents |
|------|----------|
| `stacks/` | Compose files per stack |
| `stacks/core/` | AdGuard + Homepage |
| `stacks/maintenant/` | Monitoring |
| `stacks/opencanary/` | LAN honeypot + ntfy alerter |
| `stacks/crowdsec/` | CrowdSec |
| `caddy/` | Caddyfile example |
| `homepage/` | Homepage config |
| `scripts/` | Autostart, status sync, deploy, backup |
| `site/` | Portfolio `index.html` snapshot |

## Stacks

| Stack | Role |
|-------|------|
| AdGuard Home + Unbound | DNS filtering and recursive DNS |
| Caddy | Reverse proxy and TLS (DNS-01) |
| Maintenant | Uptime checks, metrics, logs, status page |
| CrowdSec | Log-based detection and firewall bans |
| OpenCanary | LAN honeypot; ntfy on probe |
| Wazuh | SIEM |
| Nextcloud | File sync |
| Paperless-ngx | Document OCR and archive |
| SearXNG | Meta search |
| ntfy | Push notifications |
| Stalwart | Local IMAP/SMTP (mail storage and relay) |
| Roundcube | Webmail UI at mail.dobasmp.net |
| Homepage | LAN dashboard |
| terminal-gateway | Read-only public shell over tunnel |
| Restic | Nightly encrypted backups to USB |

## Host notes

- Dell OptiPlex 5040, i7-6700, 32 GB RAM, SSD
- Ubuntu, Docker Compose
- Public site on Cloudflare Pages; status from Maintenant via cron
- No inbound ports required for the portfolio path (Pages + outbound tunnels)

## Safety

Do not commit `.env`, tokens, passwords, or private keys. Examples use placeholders only.
