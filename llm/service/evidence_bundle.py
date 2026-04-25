"""
evidence_bundle.py — Builds sanitized evidence bundles from Wazuh alerts.

Raw Wazuh alert data is never passed to the LLM. This module:
  1. Fetches alerts from the Wazuh API using a read-only JWT token
  2. Maps alert fields to the typed evidence_bundle.json schema
  3. Sanitizes all string fields (truncation + character escaping + injection detection)
  4. Validates the bundle against the JSON Schema before returning

Constitution compliance:
  Article V   — logs are evidence, not instructions; content never executed
  Article VI  — injection keyword detection on high-risk string fields
  Article III — uses read-only Wazuh credentials only
"""

from __future__ import annotations

import json
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx
import jsonschema

# ── Injection detection ────────────────────────────────────────────────────────
# Keywords that indicate an adversary may have embedded LLM instructions in
# a log field (e.g. a DNS query or TLS SNI hostname).
_INJECTION_KEYWORDS = [
    "ignore",
    "instructions",
    "system",
    "admin",
    "unrestricted",
    "dan",
    "stop",
    "disregard",
    "jailbreak",
    "override",
]

# Characters that could be used to break out of JSON or prompt context
_UNSAFE_CHARS = re.compile(r"[<>{}`|]")

# Load schema once at import time
_SCHEMA_PATH = Path(__file__).parent / "schema" / "evidence_bundle.json"
_BUNDLE_SCHEMA: dict = json.loads(_SCHEMA_PATH.read_text(encoding="utf-8"))

# Field maxLength values extracted from schema for sanitization
_FIELD_MAX_LENGTHS: dict[str, int] = {
    prop: defn.get("maxLength", 512)
    for prop, defn in _BUNDLE_SCHEMA["properties"]["alerts"]["items"][
        "properties"
    ].items()
    if isinstance(defn, dict) and "maxLength" in defn
}


class BundleValidationError(Exception):
    """Raised when the assembled bundle fails JSON Schema validation."""


class EvidenceBundleBuilder:
    """
    Fetches Wazuh alerts and constructs sanitized evidence bundles.

    Usage:
        builder = EvidenceBundleBuilder(wazuh_url, username, password)
        alerts  = builder.fetch_by_window(minutes=60)
        bundle  = builder.build(alerts)
    """

    def __init__(self, wazuh_url: str, username: str, password: str) -> None:
        self._wazuh_url = wazuh_url.rstrip("/")
        self._username = username
        self._password = password
        self._token: str | None = None

    # ── Authentication ─────────────────────────────────────────────────────

    def _authenticate(self) -> str:
        """Obtain a JWT from the Wazuh API. Caches token on the instance."""
        resp = httpx.post(
            f"{self._wazuh_url}/security/user/authenticate",
            auth=(self._username, self._password),
            verify=False,  # self-signed cert in dev; operator should add CA in prod
            timeout=10.0,
        )
        resp.raise_for_status()
        self._token = resp.json()["data"]["token"]
        return self._token

    def _get_token(self) -> str:
        if self._token is None:
            self._authenticate()
        return self._token  # type: ignore[return-value]

    def _headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self._get_token()}"}

    def _get(self, path: str, params: dict | None = None) -> dict:
        """GET from Wazuh API; refreshes token once on 401."""
        url = f"{self._wazuh_url}{path}"
        try:
            resp = httpx.get(
                url, headers=self._headers(), params=params, verify=False, timeout=15.0
            )
            if resp.status_code == 401:
                self._token = None
                resp = httpx.get(
                    url,
                    headers=self._headers(),
                    params=params,
                    verify=False,
                    timeout=15.0,
                )
            resp.raise_for_status()
            return resp.json()
        except httpx.RequestError as exc:
            raise ConnectionError(f"Wazuh API unreachable: {exc}") from exc

    # ── Fetch ──────────────────────────────────────────────────────────────

    def fetch_by_ids(self, alert_ids: list[str]) -> list[dict]:
        """Fetch specific alerts by their Wazuh alert IDs."""
        if not alert_ids:
            return []
        # Wazuh indexer query via manager API
        query = {
            "query": {
                "terms": {"_id": alert_ids}
            }
        }
        data = self._get("/api/v1/alerts", params={"q": json.dumps(query), "limit": len(alert_ids)})
        return data.get("data", {}).get("affected_items", [])

    def fetch_by_window(self, minutes: int) -> list[dict]:
        """Fetch all alerts generated in the last N minutes."""
        from datetime import timedelta
        since = (datetime.now(timezone.utc) - timedelta(minutes=minutes)).isoformat()
        data = self._get(
            "/api/v1/alerts",
            params={"q": f"timestamp>{since}", "limit": 500, "sort": "-timestamp"},
        )
        return data.get("data", {}).get("affected_items", [])

    # ── Build ──────────────────────────────────────────────────────────────

    def build(self, alerts: list[dict]) -> dict:
        """
        Construct and validate a sanitized evidence bundle from raw Wazuh alerts.

        Raises:
            BundleValidationError: if the assembled bundle fails schema validation
        """
        bundle_alerts = [self._map_alert(a) for a in alerts]
        src_ips = list({a["src_ip"] for a in bundle_alerts if a.get("src_ip")})[:20]
        rule_ids = list({a["rule_id"] for a in bundle_alerts if a.get("rule_id")})

        bundle = {
            "bundle_id": str(uuid.uuid4()),
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "alerts": bundle_alerts,
            "context": {
                "time_window_minutes": None,
                "total_alerts_in_window": len(alerts),
                "unique_src_ips": src_ips,
                "rule_ids_present": rule_ids,
            },
        }

        try:
            jsonschema.validate(bundle, _BUNDLE_SCHEMA)
        except jsonschema.ValidationError as exc:
            raise BundleValidationError(f"Bundle failed schema validation: {exc.message}") from exc

        return bundle

    # ── Field mapping ──────────────────────────────────────────────────────

    def _map_alert(self, alert: dict) -> dict:
        """Map a raw Wazuh alert dict to the evidence bundle alert schema."""
        rule = alert.get("rule", {})
        data = alert.get("data", {})
        agent = alert.get("agent", {})

        # Determine log type from rule groups
        groups: list[str] = rule.get("groups", [])
        log_type = "unknown"
        for g in groups:
            if "dns" in g:
                log_type = "dns"
                break
            elif "ssl" in g or "tls" in g:
                log_type = "ssl"
                break
            elif "conn" in g or "scan" in g:
                log_type = "conn"
                break
            elif "software" in g:
                log_type = "software"
                break
            elif "notice" in g:
                log_type = "notice"
                break

        mapped: dict[str, Any] = {
            "alert_id": alert.get("id", ""),
            "rule_id": int(rule.get("id", 0)),
            "rule_description": self._sanitize("rule_description", rule.get("description", "")),
            "level": int(rule.get("level", 0)),
            "timestamp": alert.get("timestamp", datetime.now(timezone.utc).isoformat()),
            "log_type": log_type,
            "src_ip": data.get("srcip", data.get("id.orig_h", "")),
            "dst_ip": data.get("dstip", data.get("id.resp_h", "")),
            "protocol": data.get("protocol", ""),
        }

        # Optional numeric fields
        if dst_port := data.get("dstport", data.get("id.resp_p")):
            try:
                mapped["dst_port"] = int(dst_port)
            except (ValueError, TypeError):
                pass

        # DNS fields
        if dns_query := data.get("dns_query"):
            mapped["dns_query"] = self._sanitize_high_risk("dns_query", dns_query)
        if dns_rcode := data.get("dns_rcode"):
            mapped["dns_rcode"] = self._sanitize("dns_rcode", dns_rcode)

        # SSL fields
        if ssl_status := data.get("ssl_validation_status"):
            mapped["ssl_validation_status"] = self._sanitize("ssl_validation_status", ssl_status)
        if ssl_sni := data.get("ssl_server_name"):
            mapped["ssl_server_name"] = self._sanitize_high_risk("ssl_server_name", ssl_sni)

        # Connection fields
        if conn_state := data.get("conn_state"):
            mapped["conn_state"] = self._sanitize("conn_state", conn_state)
        if duration := data.get("conn_duration"):
            try:
                mapped["conn_duration_seconds"] = float(duration)
            except (ValueError, TypeError):
                pass
        for bytes_field, schema_field in [
            ("conn_orig_bytes", "conn_orig_bytes"),
            ("conn_resp_bytes", "conn_resp_bytes"),
        ]:
            if val := data.get(bytes_field):
                try:
                    mapped[schema_field] = int(val)
                except (ValueError, TypeError):
                    pass

        return mapped

    # ── Sanitization ───────────────────────────────────────────────────────

    def _sanitize(self, field_name: str, value: str) -> str:
        """
        Truncate to schema maxLength and replace unsafe characters.
        Safe for fields that are not high-risk injection vectors.
        """
        max_len = _FIELD_MAX_LENGTHS.get(field_name, 512)
        value = str(value)[:max_len]
        return _UNSAFE_CHARS.sub("[SANITIZED]", value)

    def _sanitize_high_risk(self, field_name: str, value: str) -> str:
        """
        Sanitize a high-risk field (dns_query, ssl_server_name).
        Additionally scans for injection keywords; replaces entire value if found.
        """
        max_len = _FIELD_MAX_LENGTHS.get(field_name, 256)
        original_len = len(value)
        value = str(value)[:max_len]

        # Check for injection keywords (case-insensitive)
        lower = value.lower()
        for keyword in _INJECTION_KEYWORDS:
            if keyword in lower:
                return f"[INJECTION_DETECTED: {original_len} chars]"

        return _UNSAFE_CHARS.sub("[SANITIZED]", value)

    # ── Anomaly detection ──────────────────────────────────────────────────

    def detect_anomalies(self, bundle: dict) -> list[str]:
        """
        Scan a built bundle for injection anomalies.
        Returns a list of anomaly description strings for the audit log.
        """
        anomalies: list[str] = []
        for alert in bundle.get("alerts", []):
            for field in ("dns_query", "ssl_server_name"):
                val = alert.get(field, "")
                if val.startswith("[INJECTION_DETECTED"):
                    anomalies.append(
                        f"alert_id={alert.get('alert_id')} field={field}: {val}"
                    )
        return anomalies
