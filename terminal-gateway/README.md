# terminal-gateway

Read-only WebSocket gateway for the public portfolio terminal.

## Design

| Control | Implementation |
|---------|----------------|
| Command allowlist | `ls`, `cd`, `pwd`, `cat`, `head`, `tail`, `tree`, `file`, `help`, `clear` |
| Path jail | `/opt/stacks`, `/opt/minecraft/server/config` only |
| Deny sensitive files | `.env`, `.cf.env`, `*.key`, `*.pem`, `*.db`, most dotfiles |
| Output redaction | IPs, emails, token-like strings |
| Container hardening | read-only rootfs, UID 10001, `cap_drop: ALL`, `no-new-privileges` |
| Exposure | `127.0.0.1:7681` → Cloudflare quick tunnel (outbound only) |

Full application code lives on the homelab host; this folder ships the **Docker deployment pattern**.

## Run

```bash
docker compose --profile quick-tunnel up -d --build
```

After restart, sync the new `trycloudflare.com` URL into your site's `ws-config.json` (see `site/ws-config.example.json`).

## Audit

Session commands append to `./data/audit.log` on the host (not exposed via the terminal).
