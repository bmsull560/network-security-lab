# Gate Evidence: Read-Only Enforcement Gate

**Gate:** 11 — Read-Only Enforcement  
**Phase:** 6 — LLM Analyst Assistant  
**Date:** 2026-04-25  
**Reviewer:** LLM Safety Architect  
**Status:** PASS (static review; live API tests pending running stack)

---

## What Was Tested

Static review of `policy.py`, `policy.yaml`, `main.py`, and `docker-compose.yml` to verify the LLM service cannot call any mutating Wazuh API endpoint.

## Evidence

### Policy YAML Coverage

| Forbidden Pattern | Covered | Notes |
|---|---|---|
| `PUT *` | PASS | `forbidden_patterns` in `policy.yaml` |
| `POST *` (except auth) | PASS | Regex excludes `/security/user/authenticate` |
| `DELETE *` | PASS | `forbidden_patterns` in `policy.yaml` |
| `PATCH *` | PASS | `forbidden_patterns` in `policy.yaml` |
| `/active-response` (any method) | PASS | Explicit path pattern |
| `/rules` PUT | PASS | Explicit path + method pattern |
| `/decoders` PUT | PASS | Explicit path + method pattern |

### PolicyBroker Logic

| Check | Result | Notes |
|---|---|---|
| Forbidden patterns evaluated before allowed tools | PASS | `policy.py` — forbidden check runs first |
| Default deny when no pattern matches | PASS | `policy.py` — returns `allowed=False` if no allowlist match |
| `check()` returns `allowed=False` for PUT | PASS | Static analysis |
| `check()` returns `allowed=False` for DELETE | PASS | Static analysis |
| `check()` returns `allowed=True` for `GET /api/v1/alerts` | PASS | Matches `get_alerts` tool |

### Service Account Isolation

| Check | Result | Notes |
|---|---|---|
| LLM service uses `WAZUH_READONLY_USERNAME` | PASS | `evidence_bundle.py` reads `WAZUH_READONLY_USERNAME` env var |
| Read-only credentials separate from admin credentials | PASS | Different env vars; admin creds not mounted into `llm-service` |
| Wazuh RBAC role creation documented | PASS | `docs/wazuh-api.md` |

### Compose Security

| Check | Result | Notes |
|---|---|---|
| `llm-service` port 8080 bound to `127.0.0.1` only | PASS | `docker-compose.yml` ports section |
| Ollama port 11434 not exposed to host | PASS | No `ports` section on `ollama` service |
| `llm-service` runs as non-root (`appuser`) | PASS | `Dockerfile` USER directive |

## Pending (requires live stack)

| Check | Status |
|---|---|
| `curl -X PUT https://localhost:55000/rules` with LLM token returns 403 | PENDING |
| `curl -X DELETE https://localhost:55000/api/v1/alerts` with LLM token returns 403 | PENDING |
| `curl -X POST https://localhost:55000/active-response` with LLM token returns 403 | PENDING |
| PolicyBroker blocks call before it reaches Wazuh (audit log shows `allowed=false`) | PENDING |

## Reviewer Sign-Off

**Reviewer:** LLM Safety Architect  
**Role:** LLM Safety Architect  
**Date:** 2026-04-25  
**Decision:** PASS (static review)  
**Notes:** Policy broker correctly blocks all write patterns by code review. Live API tests required before Phase 7 promotion. Run the four pending checks above and update this file.
