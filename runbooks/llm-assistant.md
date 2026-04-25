# Runbook: LLM Analyst Assistant

The LLM analyst is a **read-only** assistant. It summarizes Wazuh alerts, identifies patterns, and suggests investigation steps. It cannot block IPs, modify rules, or take any action on any system.

## Starting the Service

The LLM service starts automatically with `make up`. It depends on both Ollama and the Wazuh manager being healthy.

```bash
make up
make status   # all five containers should show "healthy"
```

On first start, Ollama pulls the configured model (default: `mistral:7b-instruct`). This can take several minutes depending on your internet connection and hardware. Monitor progress:

```bash
make llm-logs
# or
docker logs -f ollama
```

The `llm-service` container will not become healthy until Ollama is healthy (model pull complete).

## Checking Service Health

```bash
curl -s http://localhost:8080/health | jq .
```

Expected response when everything is running:
```json
{
  "status": "ok",
  "ollama": "reachable",
  "wazuh_api": "reachable"
}
```

If `ollama` shows `unreachable`, the model is still being pulled. Wait and retry.

## Analyzing Alerts

### By time window (most common)

```bash
# Analyze all alerts from the last 60 minutes
curl -s -X POST http://localhost:8080/analyze \
  -H "Content-Type: application/json" \
  -d '{"time_window_minutes": 60}' | jq .
```

### By specific alert IDs

```bash
# Get alert IDs from Wazuh dashboard, then:
curl -s -X POST http://localhost:8080/analyze \
  -H "Content-Type: application/json" \
  -d '{"alert_ids": ["1745539200.123456", "1745539210.456789"]}' | jq .
```

### Both together

```bash
curl -s -X POST http://localhost:8080/analyze \
  -H "Content-Type: application/json" \
  -d '{"alert_ids": ["1745539200.123456"], "time_window_minutes": 30}' | jq .
```

### Understanding the response

```json
{
  "summary": "Three port scan attempts detected from 192.168.1.99...",
  "evidence": [
    {
      "alert_id": "1745539300.111111",
      "claim": "Source IP 192.168.1.99 made 5 rejected connections in 20 seconds",
      "confidence": "confirmed_fact"
    }
  ],
  "hypotheses": ["HYPOTHESIS: Device at 192.168.1.99 may be compromised or misconfigured"],
  "recommended_next_steps": [
    "Check what device is at 192.168.1.99 in your DHCP leases",
    "Review conn.log for additional connections from this IP"
  ],
  "anomalies": [],
  "bundle_id": "a1b2c3d4-..."
}
```

- `confirmed_fact` — directly supported by alert data
- `hypothesis` — inferred; requires investigation to confirm
- `recommended_next_steps` — investigation actions only; no automated actions

## Daily Brief

```bash
# Summarize the last 24 hours (default)
curl -s -X POST http://localhost:8080/daily-brief \
  -H "Content-Type: application/json" \
  -d '{"hours": 24}' | jq .

# Last 12 hours
curl -s -X POST http://localhost:8080/daily-brief \
  -H "Content-Type: application/json" \
  -d '{"hours": 12}' | jq .
```

## Reading the Audit Log

Every LLM interaction is logged. The audit log is append-only and cannot be cleared by the service.

```bash
# Last 10 entries
curl -s "http://localhost:8080/audit-log?limit=10" | jq .

# Paginate
curl -s "http://localhost:8080/audit-log?limit=50&offset=50" | jq .

# Read directly from the Docker volume
docker exec llm-service tail -20 /app/audit/audit.jsonl | jq .
```

Each audit entry contains:
- `timestamp` — when the call was made
- `prompt_hash` / `response_hash` — SHA-256 of the full prompt and response
- `bundle_id` — links to the evidence bundle used
- `injection_anomalies` — any injection payloads detected in log fields
- `tool_calls` — which Wazuh API calls were made and whether they were allowed

## Changing the Ollama Model

1. Edit `docker/.env` — change `OLLAMA_MODEL`
2. Pull the new model:
   ```bash
   make ollama-pull
   ```
3. Restart the LLM service:
   ```bash
   docker restart llm-service
   ```

Recommended models by hardware:

| Hardware | Model |
|---|---|
| CPU only (8GB RAM) | `phi3:mini` or `mistral:7b-instruct` (slow) |
| GPU 8GB VRAM | `mistral:7b-instruct` |
| GPU 16GB+ VRAM | `llama3:8b` or `mixtral:8x7b` |

## OpenRouter (Not Implemented in Phase 6)

Setting `LLM_BACKEND=openrouter` in `docker/.env` will cause `/analyze` and `/daily-brief` to return HTTP 501. OpenRouter support is planned for Phase 7.

When implemented, only sanitized evidence bundles will be sent — never raw log lines.

## Troubleshooting

### Ollama takes too long to start

The model pull can take 5–20 minutes on a slow connection. The `llm-service` will wait. Monitor with:
```bash
docker logs -f ollama
```

### Model not found error

```bash
make ollama-pull
```

### Wazuh API authentication failure

Check that `WAZUH_READONLY_USERNAME` and `WAZUH_READONLY_PASSWORD` are set in `docker/.env` and that the read-only user exists in Wazuh. See `docs/wazuh-api.md` for setup instructions.

### LLM returns HTTP 422 (schema validation failed)

The model returned a response that doesn't match the required JSON schema. This can happen with smaller models. Try:
1. A larger model (`llama3:8b` instead of `phi3:mini`)
2. Increase `LLM_TIMEOUT_SECONDS` in `docker/.env`
3. Check `make llm-logs` for the raw response

### No alerts found (HTTP 404)

No alerts exist in the requested time window. Run a simulation first:
```bash
bash scripts/simulate/dns-queries.sh
bash scripts/simulate/port-scan.sh
```
Then retry `/analyze` with `{"time_window_minutes": 5}`.
