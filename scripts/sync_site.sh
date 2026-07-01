#!/usr/bin/env bash
# Sync status.json to Cloudflare Pages. Run from cron on the homelab host.
set -e
SITE=/opt/stacks/site
HASHFILE="$SITE/.status.hash"
METRIC_STAMP="$SITE/.metrics.deploy"
METRIC_INTERVAL=600

sudo python3 /opt/stacks/fetch_status.py

NEW=$(python3 - <<'PY'
import hashlib, json, pathlib
d = json.loads(pathlib.Path("/opt/stacks/site/status.json").read_text())
d.pop("hostResources", None)
rel = d.get("reliability") or {}
rel.pop("generatedAt", None)
d["reliability"] = rel
print(hashlib.sha256(json.dumps(d, sort_keys=True, separators=(",", ":")).encode()).hexdigest())
PY
)
OLD=""
[ -f "$HASHFILE" ] && OLD=$(cat "$HASHFILE")

NOW=$(date +%s)
LAST=0
[ -f "$METRIC_STAMP" ] && LAST=$(cat "$METRIC_STAMP")
METRIC_DUE=0
[ $((NOW - LAST)) -ge "$METRIC_INTERVAL" ] && METRIC_DUE=1

if [ "$NEW" = "$OLD" ] && [ "$METRIC_DUE" -eq 0 ]; then
  echo "status unchanged, skip deploy"
  exit 0
fi

echo "$NEW" | sudo tee "$HASHFILE" >/dev/null
echo "$NOW" | sudo tee "$METRIC_STAMP" >/dev/null
/opt/stacks/deploy_pages.sh
