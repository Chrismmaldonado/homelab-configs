# homelab-configs

Sanitized configs for the homelab behind [christopher.isageek.net](https://christopher.isageek.net).

No secrets, tokens, or live credentials. Domains appear as examples where needed.

## Layout

| Path | Contents |
|------|----------|
| `stacks/` | Compose files per stack |
| `stacks/core/` | AdGuard + Homepage |
| `stacks/stalwart/` | Mail server (IMAP/SMTP) |
| `stacks/roundcube/` | Webmail UI |
| `stacks/cloudflared-mail/` | Cloudflare Tunnel for webmail |
| `stacks/mail-setup/` | Profile hosting (examples only in git) |
| `stacks/maintenant/` | Monitoring |
| `stacks/opencanary/` | LAN honeypot + ntfy alerter |
| `stacks/crowdsec/` | CrowdSec |
| `caddy/` | Caddyfile example |
| `homepage/` | Homepage config |
| `scripts/` | Autostart, status sync, deploy, backup |
| `site/` | Portfolio snapshot for Cloudflare Pages |

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
| Stalwart | IMAP/SMTP; outbound relay optional |
| Roundcube | Webmail at mail.dobasmp.net |
| cloudflared-mail | Public webmail tunnel |
| Homepage | LAN dashboard |
| terminal-gateway | Read-only public shell over tunnel |
| Restic | Nightly encrypted backups to USB |

## Host notes

- Dell OptiPlex 5040, i7-6700, 32 GB RAM, SSD
- Ubuntu, Docker Compose
- Public site on Cloudflare Pages (`christopher-lab`); status from Maintenant via cron
- Mail: `mx.dobasmp.net` for IMAP/SMTP; `mail.dobasmp.net` for webmail (tunnel)
- Cellular Mail: Tailscale exit node to homelab (not committed; ops-only)

## Safety

Do not commit `.env`, tokens, passwords, private keys, or live WireGuard client configs.
