#!/usr/bin/env bash
set -e
SITE=/opt/stacks/site
HASHFILE=/opt/stacks/site/.status.hash
METRIC_STAMP=/opt/stacks/site/.metrics.deploy
METRIC_INTERVAL=600
PW=9450
dsudo() { echo "$PW" | sudo -S "$@"; }

dsudo python3 /opt/stacks/fetch_status.py

# Deploy on status change, or every 10m for host metrics
NEW=$(dsudo python3 - <<'PY'
import hashlib, json, pathlib
p = pathlib.Path("/opt/stacks/site/status.json")
d = json.loads(p.read_text())
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

echo "$NEW" | dsudo tee "$HASHFILE" >/dev/null
echo "$NOW" | dsudo tee "$METRIC_STAMP" >/dev/null
/opt/stacks/deploy_pages.sh
