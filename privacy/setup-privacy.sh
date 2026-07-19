#!/usr/bin/env bash
# Tailscale exit node + AdGuard DNS
set -euo pipefail

PW=9450
dsudo() { echo "$PW" | sudo -S "$@"; }

PRIVACY_DIR="/opt/stacks/privacy"
RESOLVED_DROPIN="/etc/systemd/resolved.conf.d/99-adguard-local.conf"

echo "=== Homelab privacy setup ==="

# --- Tailscale exit node + subnet routes (preserve existing default routes) ---
echo "[1/4] Configuring Tailscale exit node and routes..."

CURRENT_ROUTES=""
if command -v python3 >/dev/null 2>&1; then
  CURRENT_ROUTES=$(python3 - <<'PY'
import json, subprocess
d = json.loads(subprocess.check_output(["tailscale", "debug", "prefs"], text=True))
for r in d.get("AdvertiseRoutes") or []:
    print(r)
PY
)
fi

ROUTES=("192.168.1.0/24")
while IFS= read -r route; do
  [[ -z "$route" ]] && continue
  case "$route" in
    0.0.0.0/0|::/0)
      ROUTES+=("$route")
      ;;
  esac
done <<< "$CURRENT_ROUTES"

# Deduplicate while preserving order
UNIQUE_ROUTES=()
for r in "${ROUTES[@]}"; do
  seen=0
  for u in "${UNIQUE_ROUTES[@]:-}"; do
    [[ "$u" == "$r" ]] && seen=1 && break
  done
  [[ $seen -eq 0 ]] && UNIQUE_ROUTES+=("$r")
done

ROUTE_CSV=$(IFS=,; echo "${UNIQUE_ROUTES[*]}")
echo "  Advertise routes: $ROUTE_CSV"

dsudo tailscale set --advertise-exit-node --advertise-routes="$ROUTE_CSV"

# --- IP forwarding ---
echo "[2/4] Verifying IPv4 forwarding..."
FORWARD=$(sysctl -n net.ipv4.ip_forward)
if [[ "$FORWARD" != "1" ]]; then
  echo "  Enabling net.ipv4.ip_forward..."
  dsudo sysctl -w net.ipv4.ip_forward=1
  if ! grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.d/99-ip-forward.conf 2>/dev/null; then
    echo 'net.ipv4.ip_forward=1' | dsudo tee /etc/sysctl.d/99-ip-forward.conf >/dev/null
  fi
else
  echo "  net.ipv4.ip_forward already enabled"
fi

# --- Homelab uses local AdGuard for its own DNS ---
echo "[3/4] Pointing homelab DNS to local AdGuard (127.0.0.1)..."

dsudo mkdir -p /etc/systemd/resolved.conf.d
dsudo tee "$RESOLVED_DROPIN" >/dev/null <<'EOF'
# Managed by /opt/stacks/privacy/setup-privacy.sh
# AdGuard Home binds host :53; homelab queries it directly.
[Resolve]
DNS=127.0.0.1
FallbackDNS=
DNSStubListener=no
EOF

# Remove circular link DNS (enp0s25 was set to 192.168.1.213 = this host)
IFACE=$(ip -o -4 route show to default 2>/dev/null | awk '{print $5}' | head -1 || true)
if [[ -n "$IFACE" ]]; then
  dsudo resolvectl dns "$IFACE" 127.0.0.1 2>/dev/null || true
fi
dsudo resolvectl dns tailscale0 127.0.0.1 2>/dev/null || true
dsudo systemctl restart systemd-resolved

# --- Verification ---
echo "[4/4] Verification..."
echo ""
echo "--- Tailscale status ---"
tailscale status | head -5
echo ""
echo "--- Exit node / routes ---"
tailscale debug prefs 2>/dev/null | grep -E 'AdvertiseRoutes|ExitNode' || true
echo ""
echo "--- IP forward ---"
sysctl net.ipv4.ip_forward
echo ""
echo "--- DNS (homelab) ---"
resolvectl status 2>/dev/null | head -12 || cat /etc/resolv.conf
echo ""
if ss -tlnp 2>/dev/null | grep -q ':53'; then
  echo "  AdGuard/listener on :53 — OK"
else
  echo "  WARNING: nothing listening on :53 — start AdGuard container"
fi

cat <<'NEXT'

=== Manual steps (Tailscale admin — you must do these) ===

1. Approve subnet routes (if pending):
   https://login.tailscale.com/admin/machines
   → homelab → Edit route settings → Enable 192.168.1.0/24 (and 0.0.0.0/0 if shown)

2. Approve exit node (if not already):
   Same machine page → "Use as exit node" → Enable

3. Global DNS (personal tailnet only):
   https://login.tailscale.com/admin/dns
   → Nameservers → Add custom: 100.112.109.117  (Tailscale IP of homelab)
   → Enable "Override local DNS"
   → Enable MagicDNS

4. Personal device privacy (NOT work/GFE):
   • DihhTop: run setup-dihhtop.ps1 (Cloudflare WARP — see WARP-SETUP.md)
   • iPhone: 1.1.1.1 app → WARP on (see WARP-SETUP.md)
   • Do NOT use Tailscale exit nodes on personal devices (adds lag; WARP handles ISP privacy)

5. Router DHCP (optional):
   Per-device DNS to 192.168.1.213 for AdGuard when WARP is off.
   Leave work/GFE devices untouched.

=== Recommended: Cloudflare WARP (free, fast, ISP privacy) ===
See WARP-SETUP.md on homelab at /opt/stacks/privacy/

=== Legacy (not recommended) ===
FREE-EXIT-NODE.md (Oracle exit-vps), gluetun/ (paid Mullvad)

Setup complete.
NEXT
