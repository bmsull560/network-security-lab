# Runbook: Alert Triage Workflow

**Principle:** Every remediation decision is made by a human. The LLM (Phase 6) assists with analysis only.

## Workflow Overview

```
Alert generated (Wazuh rule fires)
        │
        ▼
1. Acknowledge alert in dashboard
        │
        ▼
2. Gather evidence (related logs, timeline)
        │
        ▼
3. Assess: benign / suspicious / confirmed threat
        │
        ├── Benign → document and close
        │
        ├── Suspicious → investigate further
        │       │
        │       └── [Phase 6] Request LLM analysis
        │
        └── Confirmed threat → document incident note
                │
                └── Decide remediation (human approval required)
```

## Step 1 — Find the Alert

1. Open Wazuh dashboard: `https://localhost`
2. Navigate to **Threat Intelligence → Threat Hunting → Events**
3. Set time range to last 24 hours (or relevant window)

### Useful Filters by Rule Group

| Threat | Filter |
|---|---|
| DNS anomalies | `rule.id is one of 100901, 100910` |
| Port scan | `rule.id is one of 100903, 100904` |
| TLS anomalies | `rule.id is one of 100906, 100907` |
| All Zeek alerts | `rule.groups: zeek` |
| High severity only | `rule.level >= 8` |

## Step 2 — Gather Evidence

For each alert, collect:

- **Source IP** (`data.srcip`) — which device generated the traffic?
- **Destination IP/port** (`data.dstip`, `data.dstport`) — what was contacted?
- **Timestamp** — when did it happen?
- **Rule description** — what was detected?
- **Related events** — other alerts from the same source IP in the same time window

### Check Related Zeek Logs Directly

```bash
# DNS queries from a specific host in the last hour
tail -1000 /opt/zeek/logs/current/dns.log | jq 'select(."id.orig_h"=="192.168.1.42")'

# All connections from a suspicious host
tail -1000 /opt/zeek/logs/current/conn.log | jq 'select(."id.orig_h"=="192.168.1.42")'

# SSL connections with validation issues
tail -1000 /opt/zeek/logs/current/ssl.log | jq 'select(.validation_status != "ok")'
```

## Step 3 — Assess the Alert

### DNS Query (Rule 100901)

| Observation | Assessment |
|---|---|
| Query to known CDN/service (google.com, github.com) | Benign |
| Query to unknown domain, NOERROR response | Investigate |
| NXDOMAIN for random-looking domain | Suspicious (possible DGA) |
| Long query (>50 chars, rule 100910) | Suspicious (possible tunneling) |
| High frequency of NXDOMAIN from one host | Suspicious |

### Port Scan (Rules 100903, 100904)

| Observation | Assessment |
|---|---|
| Single REJ from known device | Likely benign (misconfigured app) |
| 5+ REJ from unknown IP | Suspicious (external scan) |
| 5+ REJ from internal IP | Investigate (compromised device?) |
| Sequential port numbers | Likely port scan |

### TLS Certificate (Rules 100906, 100907)

| Observation | Assessment |
|---|---|
| Self-signed cert, known internal server | Likely benign (dev server) |
| Self-signed cert, unknown external IP | Suspicious (possible MITM) |
| Expired cert, known service | Benign (neglected renewal) |
| Expired cert, unknown IP | Suspicious |

## Step 4 — Document the Finding

Use this incident note template:

```
INCIDENT NOTE
─────────────────────────────────────────────────────
Date/Time:    [YYYY-MM-DD HH:MM UTC]
Analyst:      [your name]
Alert ID:     [Wazuh alert ID]
Rule:         [rule ID and description]

EVIDENCE
  Source IP:      [IP]
  Destination:    [IP:port]
  Timestamp:      [from log]
  Related alerts: [list any correlated alerts]

ASSESSMENT
  Classification: [ ] Benign  [ ] Suspicious  [ ] Confirmed Threat
  Confidence:     [ ] High  [ ] Medium  [ ] Low
  Reasoning:      [explain why]

ACTION TAKEN
  [ ] No action — documented and closed
  [ ] Monitoring — watching for recurrence
  [ ] Remediation required — see below

REMEDIATION (if required — human approval mandatory)
  Proposed action: [describe]
  Approved by:     [name]
  Approval date:   [date]
  Action taken:    [describe what was done]
─────────────────────────────────────────────────────
```

## Step 5 — Remediation (Human Approval Required)

**No automated remediation.** All actions require explicit human decision.

Common remediation options:

| Threat | Possible Action |
|---|---|
| Compromised device | Isolate from network (manual switch config) |
| External port scan | Block at router/firewall (manual) |
| Malicious DNS | Block domain at DNS resolver (manual) |
| MITM suspected | Investigate affected hosts; rotate credentials |

Document every remediation action in the incident note before taking it.

## Simulation Scripts (for Testing)

```bash
# Trigger DNS alerts (rules 100901, 100910)
bash scripts/simulate/dns-queries.sh

# Trigger port scan alerts (rules 100903, 100904)
bash scripts/simulate/port-scan.sh 127.0.0.1

# Trigger TLS alerts (rules 100906, 100907)
bash scripts/simulate/ssl-badcert.sh
```
