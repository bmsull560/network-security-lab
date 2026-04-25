"""
policy.py — Tool policy broker for the LLM analyst service.

Loads llm/policy.yaml and enforces allowed / approval-required / forbidden
rules on every Wazuh API call the LLM service attempts to make.

The broker is the ONLY path through which the service makes Wazuh API calls.
All check() results are returned to the caller for audit logging.

Constitution compliance:
  Article III  — LLM is read-only; all write paths are blocked here
  Article VII  — no autonomous destructive actions
  Article XIII — all tool calls are audit-logged by the caller
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml


@dataclass
class PolicyResult:
    allowed: bool
    requires_approval: bool = False
    reason: str = ""
    tool_name: str = ""


class PolicyBroker:
    """
    Enforces the tool policy defined in policy.yaml.

    Evaluation order (first match wins):
      1. forbidden_patterns  → allowed=False
      2. allowed_tools       → allowed=True
      3. approval_required_tools → allowed=True, requires_approval=True
      4. default             → allowed=False ("not in allowlist")
    """

    def __init__(self, policy_path: str = "policy.yaml") -> None:
        raw = yaml.safe_load(Path(policy_path).read_text(encoding="utf-8"))
        self._allowed: list[dict] = raw.get("allowed_tools", [])
        self._approval: list[dict] = raw.get("approval_required_tools", [])
        self._forbidden: list[dict] = raw.get("forbidden_patterns", [])

    # ── Public API ─────────────────────────────────────────────────────────

    def check(self, method: str, path: str) -> PolicyResult:
        """
        Check whether a (method, path) combination is permitted.

        Args:
            method: HTTP method in uppercase (GET, POST, PUT, DELETE, PATCH)
            path:   URL path being requested (e.g. "/api/v1/alerts")

        Returns:
            PolicyResult with allowed, requires_approval, reason, tool_name
        """
        method = method.upper()

        # 1. Forbidden patterns — checked first, unconditionally block
        for pattern in self._forbidden:
            if self._matches_forbidden(pattern, method, path):
                return PolicyResult(
                    allowed=False,
                    reason=pattern.get("reason", "Matched forbidden pattern"),
                )

        # 2. Allowed tools
        for tool in self._allowed:
            if self._matches_tool(tool, method, path):
                return PolicyResult(
                    allowed=True,
                    tool_name=tool["name"],
                    reason=f"Allowed tool: {tool['name']}",
                )

        # 3. Approval-required tools
        for tool in self._approval:
            if self._matches_tool(tool, method, path):
                return PolicyResult(
                    allowed=True,
                    requires_approval=True,
                    tool_name=tool["name"],
                    reason=f"Approval required: {tool['name']}",
                )

        # 4. Default deny
        return PolicyResult(
            allowed=False,
            reason="Not in allowlist",
        )

    # ── Private helpers ────────────────────────────────────────────────────

    def _matches_forbidden(self, pattern: dict, method: str, path: str) -> bool:
        """Return True if the request matches a forbidden pattern."""
        pattern_method = pattern.get("method", "").upper()
        pattern_path = pattern.get("path_pattern", "")

        method_match = not pattern_method or pattern_method == method
        if not method_match:
            return False

        if pattern_path:
            return bool(re.search(pattern_path, path))

        return True  # method matched, no path restriction

    def _matches_tool(self, tool: dict, method: str, path: str) -> bool:
        """Return True if the request matches a tool definition."""
        tool_method = tool.get("method", "GET").upper()
        tool_path = tool.get("path_pattern", "")

        if tool_method != method:
            return False

        if not tool_path:
            return True

        # Support simple glob-style patterns: replace * with .*
        regex = tool_path.replace("*", ".*")
        # Replace {param} placeholders with [^/]+
        regex = re.sub(r"\{[^}]+\}", r"[^/]+", regex)
        return bool(re.search(regex, path))
