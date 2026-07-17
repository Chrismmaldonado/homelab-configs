#!/bin/bash
# Generate static status pages for services that have no web UI (Caddy, CrowdSec).
# Output is mounted read-only into Caddy at /srv/status and served over TLS.
# Wire into cron every minute:  * * * * * root /opt/stacks/status-pages/refresh.sh
set -euo pipefail
OUT=/opt/stacks/status-pages
CSS='*{box-sizing:border-box}body{margin:0;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;background:#0b1012;color:#cdd6d4}
.wrap{max-width:900px;margin:0 auto;padding:2rem 1.25rem}
h1{color:#2bff9c;font-size:1.4rem;margin:0 0 .35rem}
.sub{color:#6c807e;margin:0 0 1.5rem;font-size:.9rem}
.card{background:rgba(18,26,28,.85);border:1px solid #1c2a2c;border-radius:12px;padding:1rem 1.1rem;margin-bottom:1rem}
.k{color:#5ef1ff}.ok{color:#2bff9c}.warn{color:#ffb020}.bad{color:#ff5f6e}
table{width:100%;border-collapse:collapse;font-size:.85rem}
th,td{text-align:left;padding:.45rem .35rem;border-bottom:1px solid #1c2a2c}
th{color:#6c807e;font-weight:600}
a{color:#5ef1ff;text-decoration:none}a:hover{text-decoration:underline}
code{color:#ffb020}.meta{color:#6c807e;font-size:.8rem;margin-top:1.5rem}
ul{margin:.4rem 0 0;padding-left:1.2rem;line-height:1.55}'

# --- Caddy status page: list configured proxied hosts ---
HOSTS=$(grep -E '^[a-z0-9].*\.example\.com \{' /opt/stacks/proxy/Caddyfile | sed 's/ {//' | sort)
CADDY_UP="down"
if docker ps --format '{{.Names}}' | grep -qx caddy; then CADDY_UP=up; fi
ROWS=""
while IFS= read -r h; do
  [ -z "$h" ] && continue
  ROWS="${ROWS}<tr><td><a href=\"https://${h}/\">${h}</a></td><td class=\"k\">proxied</td></tr>"
done <<< "$HOSTS"

cat > "$OUT/caddy/index.html" <<HTML
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Caddy · proxy</title><style>${CSS}</style></head><body><div class="wrap">
<h1>Caddy</h1>
<p class="sub">Reverse proxy + TLS for the homelab. This page is the local status view (Caddy has no admin UI).</p>
<div class="card"><span class="k">container</span> · <span class="$( [ "$CADDY_UP" = up ] && echo ok || echo bad )">${CADDY_UP}</span>
 · <span class="k">sites</span> · $(echo "$HOSTS" | grep -c . || echo 0)</div>
<div class="card"><strong>Configured hosts</strong>
<table><thead><tr><th>Host</th><th>Role</th></tr></thead><tbody>
${ROWS}
</tbody></table></div>
<p class="meta">Generated $(date -Is) · config: <code>/opt/stacks/proxy/Caddyfile</code></p>
</div></body></html>
HTML

# --- CrowdSec status page: engine, bouncer, decisions, collections, alerts ---
CS_UP="down"
if docker ps --format '{{.Names}}' | grep -qx crowdsec; then CS_UP=up; fi
BOUNCE=$(systemctl is-active crowdsec-firewall-bouncer 2>/dev/null || echo unknown)
ALERTS=$(docker exec crowdsec cscli alerts list -l 10 -o human 2>/dev/null || true)
COLLECTIONS=$(docker exec crowdsec cscli collections list -o human 2>/dev/null | head -25 || true)

HUMAN=$(docker exec crowdsec cscli decisions list 2>/dev/null || true)
if echo "$HUMAN" | grep -qi 'No active decisions'; then
  DEC_BLOCK="<p class=\"ok\">No active decisions — firewall is idle.</p>"
elif [ -n "$HUMAN" ]; then
  DEC_BLOCK="<pre style=\"white-space:pre-wrap;margin:0;font-size:.78rem\">$(echo "$HUMAN" | sed 's/&/\&amp;/g;s/</\&lt;/g')</pre>"
else
  DEC_BLOCK="<p class=\"warn\">Could not query decisions.</p>"
fi

cat > "$OUT/crowdsec/index.html" <<HTML
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="60">
<title>CrowdSec · IDS</title><style>${CSS}</style></head><body><div class="wrap">
<h1>CrowdSec</h1>
<p class="sub">IDS that reads Caddy + SSH logs and bans bad IPs via the host firewall bouncer. Auto-refreshes every 60s.</p>
<div class="card">
<span class="k">engine</span> · <span class="$( [ "$CS_UP" = up ] && echo ok || echo bad )">${CS_UP}</span>
 · <span class="k">firewall bouncer</span> · <span class="$( [ "$BOUNCE" = active ] && echo ok || echo warn )">${BOUNCE}</span>
</div>
<div class="card"><strong>Active decisions (bans)</strong>${DEC_BLOCK}</div>
<div class="card"><strong>Collections</strong>
<pre style="white-space:pre-wrap;margin:.5rem 0 0;font-size:.78rem">$(echo "$COLLECTIONS" | sed 's/&/\&amp;/g;s/</\&lt;/g')</pre>
</div>
<div class="card"><strong>Recent alerts</strong>
<pre style="white-space:pre-wrap;margin:.5rem 0 0;font-size:.78rem">$(echo "$ALERTS" | sed 's/&/\&amp;/g;s/</\&lt;/g')</pre>
</div>
<p class="meta">Generated $(date -Is) · CLI: <code>docker exec crowdsec cscli decisions list</code></p>
</div></body></html>
HTML

echo "refreshed status pages at $(date -Is)"
