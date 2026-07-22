# Pterodactyl (Panel + Wings)

Homelab game panel for Fabric SMP **The Boys**.

- Panel: `https://panel.dobasmp.net` → `127.0.0.1:8090`
- Wings: `https://wings.dobasmp.net` → `127.0.0.1:8091` (SFTP `:2022`)
- Compose: `docker-compose.yml` (panel/db/redis) + `wings/docker-compose.yml`
- Secrets: `/opt/stacks/pterodactyl/.env` and `.panel-admin.env` on the host (not in git)

Game files live under `/var/lib/pterodactyl/volumes/<uuid>/` with **12G** heap via the server limits / Aikar startup flags.
