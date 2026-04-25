# network-security-lab

Home/SOHO network observability and AI-assisted security analysis platform.

**Stack:** Zeek (network sensor) + Wazuh (SIEM/XDR) + Ollama (local LLM analyst)  
**Deployment:** Docker Compose on Ubuntu 24.04  
**Philosophy:** Zeek and Wazuh create evidence. The LLM helps you understand it. The LLM does not act.

---

## Architecture

```
Managed Switch (mirror port)
        │
        ▼
Zeek sensor (Ubuntu 24.04 host, direct NIC access)
        │  JSON logs → /opt/zeek/logs/current/
        ▼
Wazuh Agent (ships logs to manager)
        │
        ▼
┌─────────────────────────────────────┐
│         Docker Compose Stack        │
│  ┌─────────────┐  ┌──────────────┐  │
│  │Wazuh Manager│  │Wazuh Indexer │  │
│  └─────────────┘  └──────────────┘  │
│  ┌─────────────┐  ┌──────────────┐  │
│  │   Wazuh     │  │    Ollama    │  │
│  │  Dashboard  │  │ (LLM Phase6) │  │
│  └─────────────┘  └──────────────┘  │
└─────────────────────────────────────┘
        │
        ▼
LLM Analyst Assistant (read-only, evidence-backed, Phase 6)
```

## Prerequisites

- Ubuntu 24.04 LTS
- 8 GB RAM minimum (4 GB for Wazuh indexer)
- 50 GB disk
- Docker Engine 24+ and Docker Compose v2
- Two NICs recommended: one management, one capture (or single NIC with mirror port)
- A managed switch with SPAN/mirror port capability

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/bmsull560/network-security-lab.git
cd network-security-lab

# 2. Configure environment
cp docker/.env.example docker/.env
# Edit docker/.env — set passwords and your network details

# 3. Start the Wazuh stack
make up

# 4. Install Zeek on this host
sudo ZEEK_INTERFACE=eth1 ZEEK_NETWORK=192.168.1.0/24 bash scripts/install-zeek.sh

# 5. Install and enroll the Wazuh agent
sudo WAZUH_MANAGER_IP=127.0.0.1 bash scripts/install-agent.sh

# 6. Verify
make status
```

Dashboard: https://localhost (default credentials in `docker/.env`)

## Documentation

| Document | Purpose |
|---|---|
| [constitution/CONSTITUTION.md](constitution/CONSTITUTION.md) | Non-negotiable project principles |
| [runbooks/deployment.md](runbooks/deployment.md) | Full deployment procedure |
| [runbooks/sensor-placement.md](runbooks/sensor-placement.md) | Mirror port / SPAN configuration |
| [runbooks/incident-triage.md](runbooks/incident-triage.md) | Alert → investigation → incident note |
| [runbooks/rule-update.md](runbooks/rule-update.md) | How to add or modify detection rules |
| [runbooks/backup-restore.md](runbooks/backup-restore.md) | Backup and restore procedure |
| [docs/architecture.md](docs/architecture.md) | System architecture and data flow |
| [docs/zeek-fields.md](docs/zeek-fields.md) | Zeek log field reference |
| [docs/llm-safety.md](docs/llm-safety.md) | LLM safety design |

## Detection Coverage (MVP)

| Threat | Log Source | Rule IDs |
|---|---|---|
| DNS queries and anomalies | `dns.log` | 100901, 100902, 100905 |
| Port scan / reconnaissance | `conn.log` | 100903, 100904 |
| Self-signed TLS certificate | `ssl.log` | 100906 |
| Expired TLS certificate | `ssl.log` | 100907 |

## Project Phases

| Phase | Status | Description |
|---|---|---|
| 0 — Constitution & Governance | ✅ | Principles, repo, gates |
| 1 — Wazuh Stack | ✅ | Docker Compose deployment |
| 2 — Zeek Sensor | ✅ | Host install, JSON logging |
| 3 — Log Ingestion | ✅ | Agent shipping pipeline |
| 4 — Decoders & Rules | ✅ | DNS, port scan, SSL/TLS |
| 5 — Triage Workflow | ✅ | Runbooks, simulation scripts |
| 6 — LLM Assistant | 🔲 | Ollama, evidence bundles |
| 7 — Evidence Traceability | 🔲 | Citation hardening |
| 8 — Dashboards & Briefs | 🔲 | Daily summary |
| 9 — Hardening & Backups | 🔲 | Retention, secrets, restore |
| 10 — k3s Migration | 🔲 | Optional, ADR required |

## Running Tests

```bash
make test-rules      # Run rule regression tests against all fixtures
make test-injection  # Run prompt injection safety tests (Phase 6+)
make lint            # Lint XML, YAML, Python, shell scripts
```

## Security Notes

- The LLM assistant is **read-only by default**. It cannot block IPs, modify rules, or change configuration.
- Raw network logs **never leave the local network**. The LLM receives sanitized evidence bundles only.
- All remediation actions require **explicit human approval**.
- See [constitution/CONSTITUTION.md](constitution/CONSTITUTION.md) for the full set of non-negotiable principles.

## License

MIT
