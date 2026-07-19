#!/usr/bin/env bash
# Exclude Cloudflare Tunnel traffic from WARP
set -euo pipefail
WARP="warp-cli --accept-tos"
ranges=(
  "198.41.0.0/16"
  "162.159.0.0/16"
  "104.16.0.0/12"
)
for r in "${ranges[@]}"; do
  $WARP tunnel ip add-range "$r" 2>/dev/null && echo "excluded $r" || echo "skip $r"
done
