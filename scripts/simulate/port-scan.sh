#!/usr/bin/env bash
# simulate/port-scan.sh — Simulate port scanning activity for detection testing
#
# Connects to closed ports on a target host, generating REJ entries in
# Zeek conn.log. Five or more rejections in 20 seconds triggers rule 100904.
#
# Usage:
#   bash scripts/simulate/port-scan.sh [TARGET_IP]
#
# Arguments:
#   TARGET_IP   IP address to scan (default: 127.0.0.1)
#               Use a host on your local network that has no services on
#               ports 5555-5564. The Linux kernel will send RST automatically.
#
# Expected alerts:
#   Rule 100903 (level 7)   — each individual rejected connection
#   Rule 100904 (level 10)  — port scan detected (5+ REJ in 20s)
#
# Prerequisites:
#   - nc (netcat) installed (apt install netcat-openbsd)
#   - Zeek running and shipping logs to Wazuh
#   - Wazuh stack running (make up)
#
# WARNING: Only run against hosts you own or have explicit permission to test.

set -euo pipefail

TARGET="${1:-127.0.0.1}"
SCAN_PORTS_START=5555
SCAN_PORTS_END=5564

echo "═══════════════════════════════════════════════════════"
echo "  Port Scan Simulation"
echo "  Target: $TARGET"
echo "  Ports:  $SCAN_PORTS_START-$SCAN_PORTS_END"
echo "  Expected: Wazuh rules 100903, 100904"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "⚠  Only run against hosts you own or have permission to test."
echo ""

# Confirm if target is not localhost
if [[ "$TARGET" != "127.0.0.1" && "$TARGET" != "localhost" ]]; then
  read -r -p "Confirm scan against $TARGET? [y/N] " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted."
    exit 0
  fi
fi

echo "→ Scanning ports $SCAN_PORTS_START-$SCAN_PORTS_END on $TARGET..."
echo "  (Each connection attempt to a closed port generates a REJ in conn.log)"
echo ""

for port in $(seq "$SCAN_PORTS_START" "$SCAN_PORTS_END"); do
  echo "  → port $port"
  # -z: zero I/O mode (scan only)
  # -w 1: 1 second timeout
  # || true: don't fail on connection refused
  nc -zv -w 1 "$TARGET" "$port" 2>/dev/null || true
done

echo ""
echo "✓ Port scan simulation complete."
echo ""
echo "Check Wazuh dashboard:"
echo "  Threat Intelligence → Threat Hunting → Events"
echo "  Filter: rule.id is one of 100903, 100904"
echo ""
echo "Or check Zeek logs directly:"
echo "  tail -f /opt/zeek/logs/current/conn.log | jq 'select(.conn_state==\"REJ\") | {src: .\"id.orig_h\", dst: .\"id.resp_h\", port: .\"id.resp_p\", state: .conn_state}'"
