# homelab-configs

Reference configs and automation for my **bare-metal homelab portfolio**.

[![Live portfolio](https://img.shields.io/badge/portfolio-christopher.isageek.net-2bff9c?style=for-the-badge)](https://christopher.isageek.net)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-Chrismmaldonado-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/christopher-maldonado-86317228b/)

> Sanitized for public sharing — no secrets, tokens, or live credentials. Domains are shown as `example.com` and private IPs as placeholders.

---

## Why this repo exists

The [portfolio site](https://christopher.isageek.net) shows **live** status, architecture, and a read-only terminal. 
For **sysadmin / infrastructure / security** hiring, it answers: *Can this person document, automate, secure, and ship safely — not just install Docker once?*

---

## Architecture (high level)

```mermaid
flowchart LR
  V[Visitors] --> P[Cloudflare Pages]
  V --> T[CF Quick Tunnel]
  T --> G[terminal-gateway]
  P --> S[Static site + status.json]
  H[Homelab cron] --> S
  H --> M[Maintenant]
  G --> D[Docker stacks read-only]
  subgraph Homelab host
    C[Caddy reverse proxy] --> D
    M --> D
    CS[CrowdSec + firewall bouncer] --> C
    W[Wazuh SIEM] --> D
    R[Restic nightly] --> U[(USB backup)]
  end
```

| Layer | What it does |
|--------|----------------|
| **Cloudflare Pages** | Static portfolio, `status.json`, Pages Functions |
| **Homelab cron** | `fetch_status.py` → Maintenant endpoints + host CPU/RAM/disk → deploy if changed |
| **Quick tunnel** | Outbound WebSocket to read-only terminal (no inbound ports) |
| **Caddy** | Reverse proxy, TLS via DNS-01, per-service HTTPS |
| **Maintenant** | **One** monitoring stack: uptime probes, container/host metrics, live logs, TLS expiry, status page |
| **CrowdSec** | Reads Caddy + SSH logs, bans malicious IPs via host firewall bouncer |
| **Wazuh** | Single-node SIEM with host & Windows agents |
| **Restic** | Nightly encrypted backups of configs + DB dumps to USB |

---

## Services / stacks

| Stack | Purpose |
|-------|---------|
| **AdGuard Home + Unbound** | Network-wide DNS blocking + recursive resolver (DoH/DoT/DoQ) |
| **Caddy** | Reverse proxy + automatic TLS (Let's Encrypt DNS-01) |
| **Maintenant** | Monitoring (uptime, metrics, logs, status) |
| **CrowdSec** | Intrusion detection + automatic firewall bans |
| **Wazuh** | SIEM / security monitoring (host + Windows agent) |
| **Nextcloud** | Self-hosted personal file sync & share |
| **Paperless-ngx** | Document OCR + archive |
| **SearXNG** | Private meta search |
| **ntfy** | Self-hosted push notifications (phone alerts) |
| **Homepage** | LAN start-page dashboard |
| **terminal-gateway** | Read-only public WebSocket shell |
| **Restic** | Encrypted nightly backups to USB |


---

## Repository layout

| Path | Description |
|------|-------------|
| [`stacks/`](stacks/) | Sanitized `docker-compose.yml` for each stack |
| [`stacks/core/`](stacks/core/) | AdGuard + Homepage |
| [`stacks/maintenant/`](stacks/maintenant/) | All-in-one monitoring |
| [`stacks/crowdsec/`](stacks/crowdsec/) | CrowdSec IDS + log acquisition |
| [`stacks/nextcloud/`](stacks/nextcloud/) | Nextcloud + Postgres |
| [`stacks/paperless/`](stacks/paperless/) | Paperless-ngx stack |
| [`stacks/wazuh/`](stacks/wazuh/) | Wazuh single-node overrides |
| [`stacks/lite/`](stacks/lite/) | Unbound recursive DNS |
| [`stacks/searxng/`](stacks/searxng/) | SearXNG |
| [`stacks/ntfy/`](stacks/ntfy/) | ntfy push server |
| [`stacks/proxy/`](stacks/proxy/) | Caddy compose |
| [`caddy/Caddyfile.example`](caddy/Caddyfile.example) | Reverse proxy + TLS + status pages |
| [`homepage/`](homepage/) | Dashboard config |
| [`scripts/fetch_status.py`](scripts/fetch_status.py) | Builds live `status.json` from Maintenant + `/proc` |
| [`scripts/sync_site.sh`](scripts/sync_site.sh) | Cron-friendly sync to Cloudflare Pages |
| [`scripts/restic-backup.sh`](scripts/restic-backup.sh) | Nightly encrypted backup to USB |
| [`scripts/autostart-all.sh`](scripts/autostart-all.sh) | Boot-time stack bring-up |
| [`scripts/status-pages/`](scripts/status-pages/) | Static status pages for Caddy & CrowdSec |
| [`terminal-gateway/`](terminal-gateway/) | Read-only WebSocket shell |

---

## Security model (summary)

- **No inbound ports** on the home network for public services
- **CrowdSec** parses Caddy + SSH logs and bans malicious IPs at the host firewall
- **Wazuh** SIEM watches host + Windows endpoint for security events
- **Secrets outside deploy paths** (host-local `.env` / `.secrets` / `.cf.env`)
- **Terminal gateway:** read-only rootfs, non-root, `cap_drop: ALL`, path jail, redaction, audit log
- **TLS:** Caddy + Let's Encrypt DNS-01
- **Backups:** Restic encrypted repo on USB (7 daily / 4 weekly / 2 monthly)

See [SECURITY.md](SECURITY.md) for reporting and scope.

---

## Quick start (adapt for your lab)

```bash
# Core (DNS + dashboard)
cd stacks/core && docker compose up -d

# Reverse proxy (edit caddy/Caddyfile.example first)
cd stacks/proxy && docker compose up -d

cd stacks/maintenant && docker compose up -d

# Security
cd stacks/crowdsec && docker compose up -d

# Public read-only terminal
cd terminal-gateway && docker compose --profile quick-tunnel up -d --build

# Portfolio status sync
sudo python3 scripts/fetch_status.py
```

---

## Hardware context

Dell OptiPlex 5040 SFF — Intel Core i7-6700 (4C/8T), 32 GB RAM, 512 GB SSD + 16 GB USB backup, Ubuntu 26.04 LTS. Runs ~20+ containers with per-service memory caps alongside a modded Minecraft server — 

---

## Author

**Christopher Maldonado** — infrastructure support → sysadmin path  
Portfolio: [christopher.isageek.net](https://christopher.isageek.net) · [LinkedIn](https://www.linkedin.com/in/christopher-maldonado-86317228b/)

---

## License

[MIT](LICENSE) — use freely, no warranty.
