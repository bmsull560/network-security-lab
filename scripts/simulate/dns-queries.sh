#!/usr/bin/env bash
# simulate/dns-queries.sh — Simulate DNS query activity for detection testing
#
# Generates DNS queries that should trigger Wazuh rule 100901 (DNS query logged)
# and rule 100910 (long DNS query — possible tunneling).
#
# Usage:
#   bash scripts/simulate/dns-queries.sh
#
# Expected alerts:
#   Rule 100901 (level 5)  — for each standard DNS query
#   Rule 100910 (level 7)  — for the long domain query
#
# Prerequisites:
#   - dig installed (apt install dnsutils)
#   - Zeek running and shipping logs to Wazuh
#   - Wazuh stack running (make up)

set -euo pipefail

echo "═══════════════════════════════════════════════════════"
echo "  DNS Query Simulation"
echo "  Expected: Wazuh rules 100901, 100910"
echo "═══════════════════════════════════════════════════════"
echo ""

# ── Standard DNS queries ──────────────────────────────────────────────────────
echo "→ Generating standard DNS queries..."

DOMAINS=(
  "wazuh.com"
  "virustotal.com"
  "github.com"
  "example.com"
)

for domain in "${DOMAINS[@]}"; do
  echo "  dig $domain"
  dig "$domain" +short +time=2 +tries=1 > /dev/null 2>&1 || true
  sleep 0.5
done

# ── NXDOMAIN queries ──────────────────────────────────────────────────────────
echo ""
echo "→ Generating NXDOMAIN queries (non-existent domains)..."

NXDOMAINS=(
  "this-domain-does-not-exist-xyz123abc.com"
  "fake-malware-c2-test-only.invalid"
)

for domain in "${NXDOMAINS[@]}"; do
  echo "  dig $domain (expect NXDOMAIN)"
  dig "$domain" +short +time=2 +tries=1 > /dev/null 2>&1 || true
  sleep 0.5
done

# ── Long domain query (tunneling indicator) ───────────────────────────────────
echo ""
echo "→ Generating long DNS query (>50 chars — triggers rule 100910)..."
LONG_DOMAIN="aGVsbG8td29ybGQtdGhpcy1pcy1hLXZlcnktbG9uZy1kb21haW4tdGhhdC1taWdodC1iZS10dW5uZWxpbmcuZXhhbXBsZS5jb20"
echo "  dig $LONG_DOMAIN"
dig "$LONG_DOMAIN" +short +time=2 +tries=1 > /dev/null 2>&1 || true

echo ""
echo "✓ DNS simulation complete."
echo ""
echo "Check Wazuh dashboard:"
echo "  Threat Intelligence → Threat Hunting → Events"
echo "  Filter: rule.id is 100901 or 100910"
echo ""
echo "Or check Zeek logs directly:"
echo "  tail -f /opt/zeek/logs/current/dns.log | jq '{query: .query, rcode: .rcode_name}'"
