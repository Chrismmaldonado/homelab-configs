#!/usr/bin/env bash
# Deploy Roundcube webmail on the homelab and point mail.dobasmp.net at it.
set -euo pipefail

REPO="${REPO:-$HOME/homelab-configs}"
STACK_SRC="${STACK_SRC:-$REPO/stacks/roundcube}"
STACK_DST=/opt/stacks/roundcube
PROXY=/opt/stacks/proxy
CADDYFILE="$PROXY/Caddyfile"
MAIL_BLOCK='mail.dobasmp.net {
	import cf
	encode gzip
	reverse_proxy 127.0.0.1:3016
}'

if [ ! -f "$STACK_SRC/docker-compose.yml" ]; then
  echo "Missing $STACK_SRC/docker-compose.yml (clone/pull homelab-configs first)" >&2
  exit 1
fi

echo "=== sync roundcube stack ==="
sudo mkdir -p "$STACK_DST/config"
sudo rsync -a --delete \
  "$STACK_SRC/docker-compose.yml" \
  "$STACK_SRC/config/" \
  "$STACK_DST/"

echo "=== start roundcube ==="
( cd "$STACK_DST" && sudo docker compose up -d )

echo "=== ensure Caddy mail route ==="
if ! sudo grep -q '^mail\.dobasmp\.net {' "$CADDYFILE"; then
  sudo cp -a "$CADDYFILE" "${CADDYFILE}.bak-roundcube-$(date +%Y%m%d%H%M%S)"
  printf '\n%s\n' "$MAIL_BLOCK" | sudo tee -a "$CADDYFILE" >/dev/null
  echo "appended mail.dobasmp.net block to Caddyfile"
else
  sudo sed -i 's|reverse_proxy 127\.0\.0\.1:3015|reverse_proxy 127.0.0.1:3016|g' "$CADDYFILE"
  echo "updated existing mail.dobasmp.net backend to :3016"
fi

echo "=== reload caddy ==="
( cd "$PROXY" && sudo docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile ) \
  || ( cd "$PROXY" && sudo docker compose restart caddy )

if docker ps --format '{{.Names}}' | grep -qx snappymail; then
  echo "=== stop snappymail (replaced by roundcube) ==="
  ( cd /opt/stacks/snappymail 2>/dev/null && sudo docker compose stop ) || docker stop snappymail
fi

echo "=== health ==="
curl -fsS -o /dev/null -w 'roundcube local: %{http_code}\n' http://127.0.0.1:3016/ || true
curl -fsSk -o /dev/null -w 'mail.dobasmp.net: %{http_code}\n' https://mail.dobasmp.net/ || true

cat <<'EOF'

Done.
- LAN: https://mail.dobasmp.net (AdGuard rewrite -> 192.168.1.213)
- Away from home: same URL over HTTPS (Caddy + Cloudflare cert)
- Login: chris@dobasmp.net + your mail password

Optional phone app (off Wi-Fi): IMAP ssl://mail.dobasmp.net:993, SMTP ssl://mail.dobasmp.net:465
EOF
