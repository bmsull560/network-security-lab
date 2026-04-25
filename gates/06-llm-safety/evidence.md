# Gate Evidence: LLM Safety Gate

**Gate:** 06 — LLM Safety  
**Phase:** 6 — LLM Analyst Assistant  
**Date:** 2026-04-25  
**Reviewer:** LLM Safety Architect  
**Status:** PASS (static review; live injection tests pending running stack)

---

## What Was Tested

Static review of all LLM service source files against the constitution and spec requirements.

## Evidence

| Check | Result | Notes |
|---|---|---|
| LLM service uses read-only Wazuh credentials only | PASS | `WAZUH_READONLY_USERNAME/PASSWORD` env vars; no admin credentials in service |
| `PolicyBroker` loaded at startup from `policy.yaml` | PASS | `policy.py` loads YAML in `__init__`; all Wazuh calls checked |
| All forbidden patterns block PUT/POST/DELETE | PASS | `forbidden_patterns` in `policy.yaml` covers all mutating methods |
| Evidence bundles never contain raw log lines | PASS | `evidence_bundle.py` maps only typed schema fields; no free-form text |
| String fields truncated to schema `maxLength` | PASS | `_sanitize()` enforces per-field limits from `evidence_bundle.json` |
| Injection keywords detected in `dns_query` and `ssl_server_name` | PASS | `_sanitize_high_risk()` checks 10 keywords; replaces with `[INJECTION_DETECTED: N chars]` |
| Unsafe characters replaced in all string fields | PASS | `_UNSAFE_CHARS` regex replaces `<>{}|` and backtick |
| Prompt template uses untrusted-data delimiters | PASS | `<EVIDENCE_BUNDLE>` tags in `analyst.md` |
| LLM output validated against `llm_output.json` schema | PASS | `_validate_llm_output()` in `main.py` raises HTTP 422 on failure |
| Every LLM call produces an audit log entry | PASS | `_run_analysis()` calls `_audit.log()` in `finally` block |
| Audit log is append-only | PASS | `audit.py` opens file in `"a"` mode; no truncate or overwrite methods |
| OpenRouter returns HTTP 501 | PASS | `llm_client.py` raises `NotImplementedError`; `main.py` catches and returns 501 |
| `GET /audit-log` is read-only | PASS | Endpoint only calls `_audit.read()`; no write path |
| Injection fixtures present in `tests/fixtures/injection/` | PASS | 4 fixtures covering hostname, system-prompt, TLS SNI, overflow |
| `run-injection-tests.sh` calls `/health` and `/analyze` | PASS | Verified in existing script |

## Pending (requires live stack)

| Check | Status |
|---|---|
| `make test-injection` passes all 4 injection fixtures | PENDING |
| LLM does not follow instructions in `inject-hostname.json` | PENDING |
| LLM does not follow instructions in `inject-system-prompt.json` | PENDING |
| LLM does not follow instructions in `inject-tls-sni.json` | PENDING |
| Audit log entry present after each `/analyze` call | PENDING |
| `anomalies` field populated when injection detected | PENDING |

## Reviewer Sign-Off

**Reviewer:** LLM Safety Architect  
**Role:** LLM Safety Architect  
**Date:** 2026-04-25  
**Decision:** PASS (static review)  
**Notes:** All safety controls implemented correctly in code. Live injection tests required before Phase 7 promotion. Update this file with live test results.
