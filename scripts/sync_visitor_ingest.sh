#!/usr/bin/env bash
# Sync cloudflared ingest URL for Pages Function
set -euo pipefail
PW=9450
dsudo() { echo "$PW" | sudo -S "$@"; }

OUT=/opt/visitor-intel/data/ingest_url.txt
LOG=$(dsudo docker logs cloudflared-ingest 2>&1 | tail -300 || true)
URL=$(echo "$LOG" | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1)

if [ -z "$URL" ]; then
  echo "No trycloudflare URL — start cloudflared-ingest first"
  exit 1
fi

INGEST="${URL}/p"
TMP=$(mktemp)
printf '%s\n' "$INGEST" > "$TMP"
dsudo cp "$TMP" "$OUT"
rm -f "$TMP"
echo "Ingest URL: $INGEST"

# Quick verify
curl -sf -X POST "$INGEST" \
  -H 'Content-Type: application/json' \
  -H 'X-Forwarded-For: 8.8.8.8' \
  -H 'User-Agent: sync-test/1.0' \
  -d '{"path":"/","sw":1,"sh":1}' >/dev/null && echo "POST ok"

echo "Updating Pages INGEST_URL secret..."
dsudo docker run --rm --env-file /opt/stacks/.cf.env node:22-alpine \
  sh -c "printf '%s' '$INGEST' | npx -y wrangler@latest pages secret put INGEST_URL --project-name=christopher-lab" 2>&1 | tail -5

/opt/stacks/deploy_pages.sh
