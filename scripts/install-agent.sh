#!/usr/bin/env bash
# install-agent.sh — Install and configure the Wazuh agent on Ubuntu 24.04
#
# Usage:
#   sudo WAZUH_MANAGER_IP=<ip> bash scripts/install-agent.sh
#
# Environment variables:
#   WAZUH_MANAGER_IP          IP address of the Wazuh manager (required)
#   WAZUH_AGENT_NAME          Name for this agent (default: hostname)
#   WAZUH_REGISTRATION_PASS   Agent registration password (optional)
#                             Must match WAZUH_REGISTRATION_PASSWORD in docker/.env
#
# What this script does:
#   1. Adds the Wazuh 4.12.0 repository
#   2. Installs the Wazuh agent
#   3. Configures the manager IP and agent name
#   4. Adds the Zeek JSON log localfile stanza to ossec.conf
#   5. Enables and starts the agent service
#   6. Validates the agent is connected

set -euo pipefail

# ── Validate inputs ───────────────────────────────────────────────────────────
if [[ -z "${WAZUH_MANAGER_IP:-}" ]]; then
  echo "ERROR: WAZUH_MANAGER_IP is required."
  echo "  Example: sudo WAZUH_MANAGER_IP=192.168.1.10 bash $0"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: This script must be run as root (sudo)."
  exit 1
fi

AGENT_NAME="${WAZUH_AGENT_NAME:-$(hostname)}"
WAZUH_VERSION="4.12.0"
ZEEK_LOG_PATH="/opt/zeek/logs/current/*.log"

echo "→ Installing Wazuh Agent $WAZUH_VERSION"
echo "  Manager IP:  $WAZUH_MANAGER_IP"
echo "  Agent name:  $AGENT_NAME"
echo ""

# ── Add Wazuh repository ──────────────────────────────────────────────────────
echo "→ Adding Wazuh repository..."
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH \
  | gpg --dearmor \
  | tee /usr/share/keyrings/wazuh.gpg > /dev/null

echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
  | tee /etc/apt/sources.list.d/wazuh.list

# ── Install agent ─────────────────────────────────────────────────────────────
echo "→ Installing wazuh-agent..."
apt-get update -y
WAZUH_MANAGER="$WAZUH_MANAGER_IP" \
WAZUH_AGENT_NAME="$AGENT_NAME" \
  apt-get install -y "wazuh-agent=${WAZUH_VERSION}-*"

# ── Configure ossec.conf ──────────────────────────────────────────────────────
echo "→ Configuring /var/ossec/etc/ossec.conf..."
OSSEC_CONF="/var/ossec/etc/ossec.conf"

# Ensure manager address is set correctly
if grep -q "<address>" "$OSSEC_CONF"; then
  sed -i "s|<address>.*</address>|<address>${WAZUH_MANAGER_IP}</address>|" "$OSSEC_CONF"
fi

# Add Zeek JSON log localfile stanza if not already present
if ! grep -q "zeek" "$OSSEC_CONF"; then
  echo "→ Adding Zeek log localfile stanza..."
  # Insert before closing </ossec_config> tag
  sed -i "s|</ossec_config>|$(cat << 'STANZA'
  <!-- Zeek JSON logs — added by install-agent.sh -->
  <localfile>
    <log_format>json</log_format>
    <location>/opt/zeek/logs/current/*.log</location>
  </localfile>

</ossec_config>
STANZA
)|" "$OSSEC_CONF"
fi

# ── Copy the ossec.conf snippet from repo for reference ──────────────────────
SNIPPET="$(dirname "$0")/../wazuh/agent/ossec.conf.snippet"
if [[ -f "$SNIPPET" ]]; then
  echo "→ Reference snippet available at: $SNIPPET"
fi

# ── Enable and start agent ────────────────────────────────────────────────────
echo "→ Enabling and starting wazuh-agent service..."
systemctl daemon-reload
systemctl enable wazuh-agent
systemctl start wazuh-agent

# ── Validate connection ───────────────────────────────────────────────────────
echo "→ Waiting for agent to connect (up to 30s)..."
TIMEOUT=30
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
  STATUS=$(systemctl is-active wazuh-agent 2>/dev/null || echo "inactive")
  if [[ "$STATUS" == "active" ]]; then
    break
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

echo ""
echo "→ Agent service status:"
systemctl status wazuh-agent --no-pager | head -20

echo ""
echo "→ Agent connection log (last 10 lines):"
tail -10 /var/ossec/logs/ossec.log 2>/dev/null || echo "  (log not yet available)"

echo ""
echo "✓ Wazuh agent installation complete."
echo ""
echo "Next steps:"
echo "  1. Verify the agent appears in the Wazuh dashboard (Agents section)"
echo "  2. Generate some traffic and check Events in the dashboard"
echo "  3. Run simulation scripts: bash scripts/simulate/dns-queries.sh"
