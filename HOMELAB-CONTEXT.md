# Homelab inventory (sanitized)

Host: Dell OptiPlex (Ubuntu + Docker), LAN `192.168.1.213`, user `homelab2`.
Stacks: `/opt/stacks`. Public portfolio: [christopher.isageek.net](https://christopher.isageek.net) (Cloudflare Pages project `christopher-lab`).

## Mail

| Piece | Role |
|-------|------|
| Stalwart | IMAP 993, SMTP 465/587/25; LE certs for `mx` + `mail`; outbound via Resend relay |
| Roundcube | Webmail `127.0.0.1:3016` |
| cloudflared-mail | Tunnel hostname `mail.dobasmp.net` → Roundcube |
| mail-setup | nginx `127.0.0.1:3017` for mobileconfig (no secrets in git) |
| DNS | MX → `mx.dobasmp.net` → WAN A (DNS-only); AdGuard rewrites `mx`/`mail` → LAN on Wi‑Fi |
| Clients | iPhone Mail: `mx.dobasmp.net` 993/465; cellular uses Tailscale (exit node + LAN access) |

Do not commit Stalwart `.env`, tunnel tokens, WireGuard private keys, or password-bearing mobileconfigs.

## Public site

| Path | Role |
|------|------|
| `site/` | Pages snapshot (`index.html`, JS/CSS, `functions/`) |
| `scripts/deploy_pages.sh` | Deploy to Cloudflare Pages |
| `scripts/sync_site.sh` | Status JSON → deploy when changed |

## Other stacks

See `README.md`. Prefer useful services over dashboards. No Nextcloud/Postgres major bumps without a plan.
