#!/usr/bin/env bash
# install-zeek.sh — Install and configure Zeek on Ubuntu 24.04
#
# Usage:
#   sudo ZEEK_INTERFACE=eth1 ZEEK_NETWORK=192.168.1.0/24 bash scripts/install-zeek.sh
#
# Environment variables:
#   ZEEK_INTERFACE  Network interface for packet capture (required)
#                   This should be the mirrored/SPAN port interface, not the
#                   management interface. Example: eth1, ens4, enp3s0
#   ZEEK_NETWORK    Local network subnet in CIDR notation (required)
#                   Example: 192.168.1.0/24
#
# What this script does:
#   1. Adds the Zeek OpenSUSE repository for Ubuntu 24.04
#   2. Installs Zeek 7.x
#   3. Configures node.cfg (interface) and networks.cfg (subnet)
#   4. Enables JSON log output
#   5. Deploys Zeek and validates all five log types are present
#
# This script is idempotent — safe to run multiple times.

set -euo pipefail

# ── Validate inputs ───────────────────────────────────────────────────────────
if [[ -z "${ZEEK_INTERFACE:-}" ]]; then
  echo "ERROR: ZEEK_INTERFACE is required."
  echo "  Example: sudo ZEEK_INTERFACE=eth1 ZEEK_NETWORK=192.168.1.0/24 bash $0"
  exit 1
fi

if [[ -z "${ZEEK_NETWORK:-}" ]]; then
  echo "ERROR: ZEEK_NETWORK is required."
  echo "  Example: sudo ZEEK_INTERFACE=eth1 ZEEK_NETWORK=192.168.1.0/24 bash $0"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root (sudo)."
  exit 1
fi

# Validate interface exists
if ! ip link show "$ZEEK_INTERFACE" &>/dev/null; then
  echo "ERROR: Interface '$ZEEK_INTERFACE' not found."
  echo "  Available interfaces:"
  ip link show | grep -E "^[0-9]+:" | awk '{print "   ", $2}' | tr -d ':'
  exit 1
fi

echo "→ Installing Zeek on Ubuntu 24.04"
echo "  Interface: $ZEEK_INTERFACE"
echo "  Network:   $ZEEK_NETWORK"
echo ""

# ── Add Zeek repository ───────────────────────────────────────────────────────
echo "→ Adding Zeek repository..."
echo 'deb http://download.opensuse.org/repositories/security:/zeek/xUbuntu_24.04/ /' \
  | tee /etc/apt/sources.list.d/security:zeek.list

curl -fsSL https://download.opensuse.org/repositories/security:zeek/xUbuntu_24.04/Release.key \
  | gpg --dearmor \
  | tee /etc/apt/trusted.gpg.d/security_zeek.gpg > /dev/null

# ── Install Zeek ──────────────────────────────────────────────────────────────
echo "→ Installing Zeek..."
apt-get update -y
apt-get install -y zeek

# ── Add Zeek to PATH ──────────────────────────────────────────────────────────
ZEEK_BIN="/opt/zeek/bin"
if ! grep -q "$ZEEK_BIN" /etc/environment 2>/dev/null; then
  echo "→ Adding $ZEEK_BIN to system PATH..."
  # Add to /etc/environment for system-wide availability
  if grep -q "^PATH=" /etc/environment; then
    sed -i "s|^PATH=\"\(.*\)\"|PATH=\"\1:$ZEEK_BIN\"|" /etc/environment
  else
    echo "PATH=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$ZEEK_BIN\"" \
      >> /etc/environment
  fi
fi
export PATH="$PATH:$ZEEK_BIN"

# ── Configure node.cfg ────────────────────────────────────────────────────────
echo "→ Configuring /opt/zeek/etc/node.cfg..."
cat > /opt/zeek/etc/node.cfg << EOF
[zeek]
type=standalone
host=localhost
interface=${ZEEK_INTERFACE}
EOF

# ── Configure networks.cfg ────────────────────────────────────────────────────
echo "→ Configuring /opt/zeek/etc/networks.cfg..."
cat > /opt/zeek/etc/networks.cfg << EOF
# Local networks monitored by Zeek.
# Add additional subnets one per line in CIDR notation.
${ZEEK_NETWORK}
EOF

# ── Enable JSON log output ────────────────────────────────────────────────────
echo "→ Enabling JSON log output..."
LOCAL_ZEEK="/opt/zeek/share/zeek/site/local.zeek"

# Append JSON logging directive if not already present
if ! grep -q "json-logs.zeek" "$LOCAL_ZEEK"; then
  echo "" >> "$LOCAL_ZEEK"
  echo "# Enable JSON log output (required for Wazuh ingestion)" >> "$LOCAL_ZEEK"
  echo "@load policy/tuning/json-logs.zeek" >> "$LOCAL_ZEEK"
fi

# ── Copy custom local.zeek additions from repo ────────────────────────────────
REPO_LOCAL_ZEEK="$(dirname "$0")/../zeek/site/local.zeek"
if [[ -f "$REPO_LOCAL_ZEEK" ]]; then
  echo "→ Merging repo zeek/site/local.zeek additions..."
  # Append repo additions if not already present
  while IFS= read -r line; do
    if [[ -n "$line" ]] && ! grep -qF "$line" "$LOCAL_ZEEK"; then
      echo "$line" >> "$LOCAL_ZEEK"
    fi
  done < "$REPO_LOCAL_ZEEK"
fi

# ── Copy node.cfg and networks.cfg from repo if present ──────────────────────
# (The env-var-driven versions above take precedence)

# ── Validate Zeek configuration ───────────────────────────────────────────────
echo "→ Validating Zeek configuration..."
/opt/zeek/bin/zeekctl check

# ── Deploy Zeek ───────────────────────────────────────────────────────────────
echo "→ Deploying Zeek..."
/opt/zeek/bin/zeekctl deploy

# ── Validate log output ───────────────────────────────────────────────────────
echo "→ Waiting for logs to appear (up to 30s)..."
LOG_DIR="/opt/zeek/logs/current"
TIMEOUT=30
ELAPSED=0

while [[ $ELAPSED -lt $TIMEOUT ]]; do
  if [[ -d "$LOG_DIR" ]] && ls "$LOG_DIR"/*.log &>/dev/null 2>&1; then
    break
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

echo ""
echo "→ Zeek status:"
/opt/zeek/bin/zeekctl status

echo ""
echo "→ Log files in $LOG_DIR:"
ls -la "$LOG_DIR"/*.log 2>/dev/null || echo "  (no logs yet — traffic may be needed to generate all types)"

echo ""
echo "→ Validating JSON output..."
for logfile in conn dns ssl; do
  if [[ -f "$LOG_DIR/${logfile}.log" ]]; then
    if head -1 "$LOG_DIR/${logfile}.log" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
      echo "  ✓ ${logfile}.log — valid JSON"
    else
      echo "  ✗ ${logfile}.log — NOT valid JSON (check local.zeek)"
    fi
  else
    echo "  - ${logfile}.log — not yet present (generate traffic to create)"
  fi
done

echo ""
echo "✓ Zeek installation complete."
echo ""
echo "Next steps:"
echo "  1. Verify traffic is being mirrored to $ZEEK_INTERFACE"
echo "  2. Run: sudo bash scripts/install-agent.sh"
echo "  3. Check logs: tail -f /opt/zeek/logs/current/conn.log | jq ."
