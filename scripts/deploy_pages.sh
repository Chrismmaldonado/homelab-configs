#!/usr/bin/env bash
# Deploy /opt/stacks/site to Cloudflare Pages
# Token: /opt/stacks/.cf.env (not in deploy tree)
set -euo pipefail
SITE=/opt/stacks/site
ENVFILE=/opt/stacks/.cf.env
PROJECT=christopher-lab
PW=9450
dsudo() { echo "$PW" | sudo -S "$@"; }

if [ ! -f "$ENVFILE" ]; then
  echo "ERROR: $ENVFILE not found. Create it with CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID."
  exit 1
fi

# Pages Function env — INGEST_URL in wrangler.toml; WS_URL via `wrangler pages secret` only (avoids binding conflict)
WRANGLER="$SITE/wrangler.toml"
INGEST_URL=""
[ -f /opt/visitor-intel/data/ingest_url.txt ] && INGEST_URL=$(dsudo cat /opt/visitor-intel/data/ingest_url.txt)

if [ -n "$INGEST_URL" ]; then
  TMPW=$(mktemp)
  cat > "$TMPW" <<EOF
name = "$PROJECT"
compatibility_date = "2024-09-23"
pages_build_output_dir = "."

[vars]
INGEST_URL = "$INGEST_URL"
EOF
  dsudo cp "$TMPW" "$WRANGLER"
  rm -f "$TMPW"
  echo "wrangler.toml: INGEST_URL set"
else
  dsudo rm -f "$WRANGLER"
fi

echo "=== whoami ==="
dsudo docker run --rm --cpus=0.5 --memory=1536m --cpu-shares=128 --blkio-weight=50 -e npm_config_cache=/root/.npm -v /opt/stacks/.wrangler-cache:/root/.npm --env-file "$ENVFILE" node:22-alpine \
  sh -c "npx -y wrangler@latest whoami" 2>&1 | tail -n 8 || true

echo "=== ensure project exists ==="
dsudo docker run --rm --cpus=0.5 --memory=1536m --cpu-shares=128 --blkio-weight=50 -e npm_config_cache=/root/.npm -v /opt/stacks/.wrangler-cache:/root/.npm --env-file "$ENVFILE" node:22-alpine \
  sh -c "npx -y wrangler@latest pages project create $PROJECT --production-branch=main" 2>&1 | tail -n 5 || true

echo "=== deploy ==="
DEPLOY_OUT=$(dsudo docker run --rm --cpus=0.5 --memory=1536m --cpu-shares=128 --blkio-weight=50 -e npm_config_cache=/root/.npm -v /opt/stacks/.wrangler-cache:/root/.npm --env-file "$ENVFILE" -v "$SITE":/site -w /site node:22-alpine \
  sh -c "npx -y wrangler@latest pages deploy /site --project-name=$PROJECT --branch=main --commit-dirty=true" 2>&1)
echo "$DEPLOY_OUT" | tail -n 25

if echo "$DEPLOY_OUT" | grep -qiE 'success|deployed|Deployment complete'; then
  DEPLOY_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf '{"deployedAt":"%s","project":"%s"}\n' "$DEPLOY_TS" "$PROJECT" > /tmp/.deploy.json
  dsudo cp /tmp/.deploy.json "$SITE/.deploy.json"
  echo "Wrote $SITE/.deploy.json ($DEPLOY_TS)"
else
  echo "WARNING: deploy may have failed — .deploy.json not updated"
  exit 1
fi
