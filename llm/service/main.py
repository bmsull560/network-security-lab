"""
main.py — FastAPI application for the LLM analyst service.

Endpoints:
  GET  /health        — liveness + dependency check
  POST /analyze       — analyze alerts by ID or time window
  POST /daily-brief   — summarize last N hours of alerts
  GET  /audit-log     — paginated read of the append-only audit log

Constitution compliance:
  Article III  — LLM is read-only; PolicyBroker enforced on all Wazuh calls
  Article V    — EvidenceBundleBuilder sanitizes all log-derived strings
  Article VI   — injection anomalies detected and logged
  Article VIII — LLM output validated against llm_output.json schema
  Article XIII — every LLM call produces an audit log entry
"""

from __future__ import annotations

import json
import os
import time
import uuid
from pathlib import Path
from typing import Any, Optional

import httpx
import jsonschema
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from audit import AuditLogger
from evidence_bundle import BundleValidationError, EvidenceBundleBuilder
from llm_client import LLMClient, LLMUnavailableError
from policy import PolicyBroker

# ── Configuration from environment ────────────────────────────────────────────

OLLAMA_URL = os.getenv("OLLAMA_URL", "http://ollama:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "mistral:7b-instruct")
LLM_BACKEND = os.getenv("LLM_BACKEND", "ollama")
LLM_TIMEOUT = int(os.getenv("LLM_TIMEOUT_SECONDS", "120"))
WAZUH_API_URL = os.getenv("WAZUH_API_URL", "https://wazuh-manager:55000")
WAZUH_USER = os.getenv("WAZUH_READONLY_USERNAME", "llm-analyst")
WAZUH_PASS = os.getenv("WAZUH_READONLY_PASSWORD", "")
AUDIT_LOG_PATH = os.getenv("AUDIT_LOG_PATH", "/app/audit/audit.jsonl")

# ── Load supporting artifacts ──────────────────────────────────────────────────

_BASE = Path(__file__).parent

_PROMPT_TEMPLATE = (_BASE / "prompts" / "analyst.md").read_text(encoding="utf-8")
_OUTPUT_SCHEMA: dict = json.loads(
    (_BASE / "schema" / "llm_output.json").read_text(encoding="utf-8")
)

# ── Singletons ─────────────────────────────────────────────────────────────────

_audit = AuditLogger(AUDIT_LOG_PATH)
_policy = PolicyBroker(str(_BASE / "policy.yaml"))
_llm = LLMClient(
    backend=LLM_BACKEND,
    ollama_url=OLLAMA_URL,
    ollama_model=OLLAMA_MODEL,
    timeout_seconds=LLM_TIMEOUT,
)
_builder = EvidenceBundleBuilder(WAZUH_API_URL, WAZUH_USER, WAZUH_PASS)

# ── FastAPI app ────────────────────────────────────────────────────────────────

app = FastAPI(
    title="NSM LLM Analyst",
    description="Read-only LLM analyst for Zeek/Wazuh network security alerts.",
    version="0.1.0",
)

# ── Request / response models ──────────────────────────────────────────────────


class AnalyzeRequest(BaseModel):
    alert_ids: Optional[list[str]] = Field(default=None, description="Specific Wazuh alert IDs")
    time_window_minutes: Optional[int] = Field(
        default=None, ge=1, le=1440, description="Fetch alerts from last N minutes"
    )


class DailyBriefRequest(BaseModel):
    hours: int = Field(default=24, ge=1, le=72, description="Hours to summarize")


# ── Helpers ────────────────────────────────────────────────────────────────────


def _check_wazuh_reachable() -> bool:
    try:
        r = httpx.get(f"{WAZUH_API_URL}/", verify=False, timeout=5.0)
        return r.status_code in (200, 401)
    except Exception:
        return False


def _render_prompt(bundle: dict, extra_instruction: str = "") -> str:
    """Inject the evidence bundle into the prompt template."""
    bundle_json = json.dumps(bundle, indent=2)
    prompt = _PROMPT_TEMPLATE.replace("{evidence_bundle_json}", bundle_json)
    if extra_instruction:
        prompt += f"\n\n{extra_instruction}"
    return prompt


def _validate_llm_output(raw: str) -> dict:
    """
    Parse and validate the LLM's raw response against llm_output.json schema.

    Raises:
        HTTPException 422 if the response is not valid JSON or fails schema.
    """
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise HTTPException(
            status_code=422,
            detail=f"LLM returned non-JSON response: {str(exc)[:200]}",
        )
    try:
        jsonschema.validate(parsed, _OUTPUT_SCHEMA)
    except jsonschema.ValidationError as exc:
        raise HTTPException(
            status_code=422,
            detail=f"LLM response failed schema validation: {exc.message[:300]}",
        )
    return parsed


def _run_analysis(
    bundle: dict,
    session_id: str,
    endpoint: str,
    extra_instruction: str = "",
) -> dict:
    """
    Core analysis pipeline: render prompt → call LLM → validate → audit log.
    Returns the validated LLM output dict.
    """
    # Policy check for the evidence fetch (already done by builder, but log it)
    policy_result = _policy.check("GET", "/api/v1/alerts")
    tool_calls = [
        {
            "tool": "get_alerts",
            "allowed": policy_result.allowed,
            "requires_approval": policy_result.requires_approval,
        }
    ]

    anomalies = _builder.detect_anomalies(bundle)
    prompt = _render_prompt(bundle, extra_instruction)

    t0 = time.monotonic()
    response_valid = True
    raw_response = ""

    try:
        raw_response = _llm.complete(prompt)
        result = _validate_llm_output(raw_response)
    except HTTPException:
        response_valid = False
        raise
    except NotImplementedError as exc:
        raise HTTPException(status_code=501, detail=str(exc))
    except LLMUnavailableError as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    finally:
        duration_ms = int((time.monotonic() - t0) * 1000)
        _audit.log(
            _audit.build_entry(
                session_id=session_id,
                endpoint=endpoint,
                model=OLLAMA_MODEL,
                backend=LLM_BACKEND,
                prompt=prompt,
                raw_response=raw_response,
                bundle_id=bundle.get("bundle_id", ""),
                alert_count=len(bundle.get("alerts", [])),
                tool_calls=tool_calls,
                injection_anomalies=anomalies,
                response_valid=response_valid,
                duration_ms=duration_ms,
            )
        )

    return result


# ── Endpoints ──────────────────────────────────────────────────────────────────


@app.get("/health")
async def health() -> JSONResponse:
    """
    Liveness and dependency check.
    Always returns HTTP 200; degraded state reported in body.
    """
    ollama_ok = _llm.is_reachable()
    wazuh_ok = _check_wazuh_reachable()
    return JSONResponse(
        {
            "status": "ok",
            "ollama": "reachable" if ollama_ok else "unreachable",
            "wazuh_api": "reachable" if wazuh_ok else "unreachable",
        }
    )


@app.post("/analyze")
async def analyze(req: AnalyzeRequest) -> dict:
    """
    Analyze Wazuh alerts using the local LLM.

    Accepts either alert_ids, time_window_minutes, or both.
    Returns a validated llm_output.json response.
    """
    if not req.alert_ids and req.time_window_minutes is None:
        raise HTTPException(
            status_code=400,
            detail="Provide at least one of: alert_ids, time_window_minutes",
        )

    if LLM_BACKEND == "openrouter":
        raise HTTPException(
            status_code=501,
            detail="OpenRouter backend is not implemented in Phase 6. Set LLM_BACKEND=ollama.",
        )

    # Fetch alerts
    try:
        alerts: list[dict] = []
        if req.alert_ids:
            alerts.extend(_builder.fetch_by_ids(req.alert_ids))
        if req.time_window_minutes is not None:
            window_alerts = _builder.fetch_by_window(req.time_window_minutes)
            # Deduplicate by alert id
            existing_ids = {a.get("id") for a in alerts}
            alerts.extend(a for a in window_alerts if a.get("id") not in existing_ids)
    except ConnectionError as exc:
        raise HTTPException(status_code=502, detail=str(exc))

    if not alerts:
        raise HTTPException(
            status_code=404,
            detail="No alerts found for the given criteria.",
        )

    # Build sanitized bundle
    try:
        bundle = _builder.build(alerts)
    except BundleValidationError as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    session_id = str(uuid.uuid4())
    return _run_analysis(bundle, session_id, "/analyze")


@app.post("/daily-brief")
async def daily_brief(req: DailyBriefRequest) -> dict:
    """
    Summarize all alerts from the last N hours.
    Returns a validated llm_output.json response.
    """
    if LLM_BACKEND == "openrouter":
        raise HTTPException(
            status_code=501,
            detail="OpenRouter backend is not implemented in Phase 6. Set LLM_BACKEND=ollama.",
        )

    try:
        alerts = _builder.fetch_by_window(minutes=req.hours * 60)
    except ConnectionError as exc:
        raise HTTPException(status_code=502, detail=str(exc))

    if not alerts:
        raise HTTPException(
            status_code=404,
            detail=f"No alerts found in the last {req.hours} hours.",
        )

    try:
        bundle = _builder.build(alerts)
    except BundleValidationError as exc:
        raise HTTPException(status_code=500, detail=str(exc))

    session_id = str(uuid.uuid4())
    extra = (
        f"Produce a concise daily network security brief covering the last {req.hours} hours. "
        "Highlight the most significant findings and any patterns across multiple alerts."
    )
    return _run_analysis(bundle, session_id, "/daily-brief", extra_instruction=extra)


@app.get("/audit-log")
async def audit_log(
    limit: int = Query(default=50, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
) -> dict:
    """
    Paginated read of the append-only audit log. Newest entries first.
    """
    entries, total = _audit.read(limit=limit, offset=offset)
    return {
        "entries": entries,
        "total": total,
        "limit": limit,
        "offset": offset,
    }
