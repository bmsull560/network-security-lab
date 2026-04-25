"""
llm_client.py — LLM backend client for the analyst service.

Supports:
  - ollama  (default): local inference, no data leaves the host
  - openrouter: NOT IMPLEMENTED in Phase 6 — raises HTTP 501

Constitution compliance:
  Article II  — local-first; Ollama keeps all data on-host
  Article IX  — timeout configurable; no silent hangs
"""

from __future__ import annotations

import os

import httpx


class LLMUnavailableError(Exception):
    """Raised when the LLM backend cannot be reached."""


class LLMClient:
    """
    Thin wrapper around the configured LLM backend.

    Usage:
        client = LLMClient(
            backend="ollama",
            ollama_url="http://ollama:11434",
            ollama_model="mistral:7b-instruct",
        )
        raw_text = client.complete(prompt)
    """

    def __init__(
        self,
        backend: str,
        ollama_url: str,
        ollama_model: str,
        openrouter_api_key: str = "",
        timeout_seconds: int = 120,
    ) -> None:
        self._backend = backend.lower()
        self._ollama_url = ollama_url.rstrip("/")
        self._ollama_model = ollama_model
        self._openrouter_api_key = openrouter_api_key
        self._timeout = timeout_seconds

    # ── Public API ─────────────────────────────────────────────────────────

    def complete(self, prompt: str) -> str:
        """
        Send prompt to the configured backend and return the raw response string.

        Raises:
            LLMUnavailableError: backend unreachable or timed out
            NotImplementedError: backend is 'openrouter' (Phase 6 stub)
        """
        if self._backend == "ollama":
            return self._ollama_complete(prompt)
        elif self._backend == "openrouter":
            raise NotImplementedError(
                "OpenRouter backend is not implemented in Phase 6. "
                "Set LLM_BACKEND=ollama in docker/.env."
            )
        else:
            raise ValueError(f"Unknown LLM backend: {self._backend!r}. Use 'ollama'.")

    def is_reachable(self) -> bool:
        """Return True if the Ollama service responds to a health check."""
        if self._backend != "ollama":
            return False
        try:
            resp = httpx.get(
                f"{self._ollama_url}/api/tags",
                timeout=5.0,
            )
            return resp.status_code == 200
        except Exception:
            return False

    # ── Ollama ─────────────────────────────────────────────────────────────

    def _ollama_complete(self, prompt: str) -> str:
        """
        Call Ollama /api/generate (non-streaming).

        Returns the 'response' field from the Ollama JSON response.
        """
        payload = {
            "model": self._ollama_model,
            "prompt": prompt,
            "stream": False,
        }
        try:
            resp = httpx.post(
                f"{self._ollama_url}/api/generate",
                json=payload,
                timeout=float(self._timeout),
            )
            resp.raise_for_status()
        except httpx.TimeoutException as exc:
            raise LLMUnavailableError(
                f"Ollama timed out after {self._timeout}s. "
                "Consider increasing LLM_TIMEOUT_SECONDS or using a smaller model."
            ) from exc
        except httpx.RequestError as exc:
            raise LLMUnavailableError(
                f"Cannot reach Ollama at {self._ollama_url}: {exc}"
            ) from exc
        except httpx.HTTPStatusError as exc:
            raise LLMUnavailableError(
                f"Ollama returned HTTP {exc.response.status_code}: {exc.response.text[:200]}"
            ) from exc

        data = resp.json()
        return data.get("response", "")
