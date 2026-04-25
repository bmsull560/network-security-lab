# System Architecture

## Overview

```
Managed Switch (mirror/SPAN port)
        │  All network traffic mirrored
        ▼
┌─────────────────────────────────────────────────────┐
│  Ubuntu 24.04 Sensor Host                           │
│                                                     │
│  eth0 — management (SSH, Docker)                    │
│  eth1 — capture (promiscuous, no IP required)       │
│                                                     │
│  ┌─────────────────────────────────────────────┐    │
│  │  Zeek (host install, /opt/zeek/)            │    │
│  │  Reads from eth1 via libpcap                │    │
│  │  Writes JSON logs to:                       │    │
│  │    /opt/zeek/logs/current/conn.log          │    │
│  │    /opt/zeek/logs/current/dns.log           │    │
│  │    /opt/zeek/logs/current/ssl.log           │    │
│  │    /opt/zeek/logs/current/notice.log        │    │
│  │    /opt/zeek/logs/current/software.log      │    │
│  └──────────────────┬──────────────────────────┘    │
│                     │ file read (localfile)          │
│  ┌──────────────────▼──────────────────────────┐    │
│  │  Wazuh Agent (/var/ossec/)                  │    │
│  │  Ships JSON logs to Wazuh Manager           │    │
│  │  TLS encrypted, port 1514                   │    │
│  └──────────────────┬──────────────────────────┘    │
└─────────────────────┼───────────────────────────────┘
                      │ TLS (port 1514)
                      ▼
┌─────────────────────────────────────────────────────┐
│  Docker Compose Stack                               │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │  wazuh-manager (port 1514, 1515, 55000)      │   │
│  │  - Receives agent logs                       │   │
│  │  - Applies custom decoders (zeek_decoders)   │   │
│  │  - Fires custom rules (zeek_rules)           │   │
│  │  - Forwards alerts to indexer via Filebeat   │   │
│  └──────────────────┬───────────────────────────┘   │
│                     │ HTTPS (port 9200)              │
│  ┌──────────────────▼───────────────────────────┐   │
│  │  wazuh-indexer (OpenSearch)                  │   │
│  │  - Stores and indexes all alerts             │   │
│  │  - Provides search API                       │   │
│  │  - ILM: hot 7d → warm 30d → delete          │   │
│  └──────────────────┬───────────────────────────┘   │
│                     │ HTTPS (port 9200)              │
│  ┌──────────────────▼───────────────────────────┐   │
│  │  wazuh-dashboard (port 443)                  │   │
│  │  - Operator UI for alert triage              │   │
│  │  - Threat Hunting, Events, Rules views       │   │
│  └──────────────────────────────────────────────┘   │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │  ollama (Phase 6)                            │   │
│  │  - Local LLM inference                       │   │
│  │  - No data leaves the host                   │   │
│  └──────────────────────────────────────────────┘   │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │  llm-service (Phase 6)                       │   │
│  │  - FastAPI evidence bundle builder           │   │
│  │  - Read-only Wazuh API client                │   │
│  │  - Policy broker (no write tools)            │   │
│  │  - Append-only audit log                     │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
                      │
                      ▼
              Human Operator
         (all remediation decisions)
```

## Port Map

| Port | Service | Binding | Purpose |
|---|---|---|---|
| 1514 | wazuh-manager | localhost | Agent log shipping (TCP/UDP) |
| 1515 | wazuh-manager | localhost | Agent enrollment |
| 55000 | wazuh-manager | localhost | Wazuh REST API |
| 9200 | wazuh-indexer | internal | OpenSearch API (Docker network only) |
| 443 | wazuh-dashboard | localhost | Operator UI |
| 11434 | ollama | internal | LLM inference (Docker network only, Phase 6) |
| 8080 | llm-service | localhost | Evidence bundle API (Phase 6) |

All ports are bound to `127.0.0.1` by default. Use SSH tunneling for remote access.

## Data Flow

```
Network traffic
  → Zeek (libpcap, eth1)
  → JSON log files (/opt/zeek/logs/current/)
  → Wazuh Agent (localfile, log_format=json)
  → Wazuh Manager (TLS, port 1514)
  → Decoder: zeek_decoders.xml (field extraction)
  → Rules: zeek_rules.xml (alert generation)
  → Filebeat → Wazuh Indexer (OpenSearch)
  → Wazuh Dashboard (operator view)
  → [Phase 6] LLM Service (read-only, evidence bundles)
  → [Phase 6] Ollama (local inference)
  → Operator (all decisions)
```

## Key Design Decisions

| Decision | Rationale | ADR |
|---|---|---|
| Zeek on host, not container | Reliable packet capture; avoids NET_ADMIN complexity | — |
| Docker Compose, not Kubernetes | Operational simplicity; Kubernetes deferred (Article XIV) | — |
| Ollama local, not cloud | Raw logs never leave the network (Article II) | — |
| LLM read-only | Prompt injection resistance (Articles III, VI) | — |
| Ports bound to localhost | Minimal attack surface (Article I) | — |
