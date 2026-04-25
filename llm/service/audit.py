"""
audit.py — Append-only JSONL audit logger for LLM interactions.

Every LLM call (prompt, response, tool calls, evidence bundle) is recorded
here. The log is never truncated or overwritten — only appended.

Constitution compliance:
  Article XIII — auditability of all model outputs and tool calls
  Article VII  — no destructive operations; log is append-only
"""

from __future__ import annotations

import hashlib
import json
import os
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


class AuditLogger:
    """Thread-safe append-only JSONL audit log."""

    def __init__(self, log_path: str) -> None:
        self._path = Path(log_path)
        self._path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()

    # ── Write ──────────────────────────────────────────────────────────────

    def log(self, entry: dict[str, Any]) -> None:
        """Append a single audit entry as a JSONL line. Thread-safe."""
        line = json.dumps(entry, default=str) + "\n"
        with self._lock:
            with self._path.open("a", encoding="utf-8") as fh:
                fh.write(line)

    # ── Read ───────────────────────────────────────────────────────────────

    def read(self, limit: int = 50, offset: int = 0) -> tuple[list[dict], int]:
        """
        Return (entries, total_count) newest-first.
        Reads the entire file; suitable for audit logs up to ~100k entries.
        """
        if not self._path.exists():
            return [], 0

        with self._lock:
            with self._path.open("r", encoding="utf-8") as fh:
                lines = fh.readlines()

        entries: list[dict] = []
        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                # Corrupted line — skip but don't crash
                continue

        total = len(entries)
        # Newest-first
        entries.reverse()
        return entries[offset : offset + limit], total

    # ── Helpers ────────────────────────────────────────────────────────────

    @staticmethod
    def hash_text(text: str) -> str:
        """Return SHA-256 hex digest of a string."""
        return hashlib.sha256(text.encode("utf-8")).hexdigest()

    @staticmethod
    def now_iso() -> str:
        """Return current UTC time as ISO-8601 string."""
        return datetime.now(timezone.utc).isoformat()

    def build_entry(
        self,
        *,
        session_id: str,
        endpoint: str,
        model: str,
        backend: str,
        prompt: str,
        raw_response: str,
        bundle_id: str,
        alert_count: int,
        tool_calls: list[dict],
        injection_anomalies: list[str],
        response_valid: bool,
        duration_ms: int,
    ) -> dict[str, Any]:
        """Construct a complete audit entry dict."""
        return {
            "timestamp": self.now_iso(),
            "session_id": session_id,
            "endpoint": endpoint,
            "model": model,
            "backend": backend,
            "prompt_hash": self.hash_text(prompt),
            "response_hash": self.hash_text(raw_response),
            "bundle_id": bundle_id,
            "alert_count": alert_count,
            "tool_calls": tool_calls,
            "injection_anomalies": injection_anomalies,
            "response_valid": response_valid,
            "duration_ms": duration_ms,
        }
