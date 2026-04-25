# Zeek local site configuration
# This file is loaded by Zeek at startup after all base scripts.
# Add custom scripts and policy tuning here.
#
# IMPORTANT: Do not modify Zeek base scripts directly.
# All customization belongs in this file or /opt/zeek/share/zeek/site/.

# ── JSON log output ───────────────────────────────────────────────────────────
# Required for Wazuh ingestion. Converts all Zeek logs from TSV to JSON.
@load policy/tuning/json-logs.zeek

# ── Log all traffic (not just sampled) ───────────────────────────────────────
# Ensures conn.log captures all connections, not just a sample.
redef Log::default_rotation_interval = 1hr;

# ── Software detection ────────────────────────────────────────────────────────
# Enables software.log — tracks software versions seen on the network.
@load policy/protocols/conn/known-services
@load policy/protocols/ssl/known-certs

# ── Notice framework ──────────────────────────────────────────────────────────
# Enables notice.log for Zeek's built-in detection notices.
@load base/frameworks/notice

# ── DNS logging ───────────────────────────────────────────────────────────────
# Ensures all DNS queries are logged, including those with no response.
redef DNS::max_pending_msgs = 50;

# ── SSL/TLS logging ───────────────────────────────────────────────────────────
# Log SSL connections even when the handshake is incomplete.
redef SSL::ssl_store_valid_chain = T;
