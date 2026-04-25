#!/usr/bin/env bash
# simulate/ssl-badcert.sh — Simulate TLS certificate anomalies for detection testing
#
# Connects to servers with self-signed and expired TLS certificates.
# Zeek logs these in ssl.log with validation_status set accordingly.
#
# Usage:
#   bash scripts/simulate/ssl-badcert.sh
#
# Expected alerts:
#   Rule 100906 (level 8)   — self-signed certificate
#   Rule 100907 (level 12)  — expired certificate
#
# Prerequisites:
#   - curl installed
#   - Zeek running and shipping logs to Wazuh
#   - Wazuh stack running (make up)
#   - Internet access to badssl.com test endpoints

set -euo pipefail

echo "═══════════════════════════════════════════════════════"
echo "  SSL/TLS Certificate Anomaly Simulation"
echo "  Expected: Wazuh rules 100906, 100907"
echo "═══════════════════════════════════════════════════════"
echo ""

# ── Self-signed certificate ───────────────────────────────────────────────────
echo "→ Connecting to self-signed certificate endpoint..."
echo "  curl -k https://self-signed.badssl.com"
echo "  Expected: Zeek ssl.log validation_status = 'self signed certificate'"
echo "  Expected: Wazuh rule 100906 (level 8)"
echo ""
curl -sk -o /dev/null --max-time 10 https://self-signed.badssl.com || true
sleep 1

# ── Expired certificate ───────────────────────────────────────────────────────
echo "→ Connecting to expired certificate endpoint..."
echo "  curl -k https://expired.badssl.com"
echo "  Expected: Zeek ssl.log validation_status = 'certificate has expired'"
echo "  Expected: Wazuh rule 100907 (level 12)"
echo ""
curl -sk -o /dev/null --max-time 10 https://expired.badssl.com || true
sleep 1

# ── Wrong host certificate ────────────────────────────────────────────────────
echo "→ Connecting to wrong-host certificate endpoint..."
echo "  curl -k https://wrong.host.badssl.com"
echo "  Expected: Zeek ssl.log validation_status = 'hostname mismatch'"
echo ""
curl -sk -o /dev/null --max-time 10 https://wrong.host.badssl.com || true
sleep 1

echo ""
echo "✓ SSL/TLS simulation complete."
echo ""
echo "Check Wazuh dashboard:"
echo "  Threat Intelligence → Threat Hunting → Events"
echo "  Filter: rule.id is one of 100906, 100907"
echo ""
echo "Or check Zeek logs directly:"
echo "  tail -f /opt/zeek/logs/current/ssl.log | jq '{server: .server_name, status: .validation_status, src: .\"id.orig_h\"}'"
