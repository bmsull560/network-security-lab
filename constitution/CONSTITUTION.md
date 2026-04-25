# Project Constitution — network-security-lab

**Version:** 1.0  
**Date:** 2026-04-25  
**Status:** Ratified

This constitution defines the non-negotiable operating principles of the network-security-lab platform. All implementation decisions, feature additions, and operational changes must be evaluated against these principles. A principle may only be relaxed by explicit documented decision recorded in `/adr/`.

---

## Article I — Security-First Design

**Principle:** Every component is designed with security as a primary constraint, not an afterthought.

**Rationale:** A security monitoring platform that is itself insecure undermines the entire purpose of the system.

**Required:**
- All services run with least-privilege accounts
- No service exposes unnecessary ports
- All inter-service communication is authenticated
- Default configurations are hardened before first use

**Forbidden:**
- Running services as root unless technically unavoidable and documented in an ADR
- Exposing the Wazuh API or dashboard to the public internet without explicit justification and gate approval
- Disabling TLS for inter-service communication in production

---

## Article II — Local-First / Private-by-Default

**Principle:** All log data, alert data, and network telemetry stays on the local network by default.

**Rationale:** Network logs contain sensitive information about devices, users, and behavior. Sending raw logs to cloud services is a privacy violation and a potential data exfiltration risk.

**Required:**
- Ollama runs locally; no log data leaves the host by default
- If OpenRouter is enabled, only sanitized evidence bundles are transmitted — never raw log lines
- All data-at-rest is stored on local volumes
- Retention policies are operator-controlled

**Forbidden:**
- Sending raw Zeek logs, Wazuh alerts, or full log lines to any cloud API
- Enabling cloud LLM fallback without explicit operator opt-in and documented privacy review
- Storing logs in cloud object storage without encryption and explicit operator decision

---

## Article III — Read-Only LLM by Default

**Principle:** The LLM assistant has no write access to any system component.

**Rationale:** LLMs can be manipulated via prompt injection embedded in log data. An LLM with write access is an attack surface.

**Required:**
- LLM service account has read-only access to the Wazuh API
- LLM cannot write to Wazuh configuration, rules, or decoders
- LLM cannot execute shell commands
- LLM cannot modify Docker Compose services
- All LLM tool calls are logged with full input/output

**Forbidden:**
- Giving the LLM a Wazuh API token with write permissions
- Allowing the LLM to call any endpoint that mutates state
- Auto-applying LLM-generated rules without human review

---

## Article IV — Human Approval Required for Remediation

**Principle:** No remediation action — blocking, quarantine, rule change, config change — is taken without explicit human approval.

**Rationale:** False positives in automated remediation cause outages. In a home/SOHO environment, a blocked device can mean a locked-out family member or a failed critical service.

**Required:**
- All remediation suggestions are presented as draft actions requiring approval
- Approval is a deliberate human action (not a default timeout)
- Approved actions are logged with timestamp, approver identity, and rationale

**Forbidden:**
- Automated IP blocking
- Automated firewall rule changes
- Automated Wazuh active response without human review
- Any "auto-remediate if confidence > X%" logic

---

## Article V — Logs Are Evidence, Not Instructions

**Principle:** Log data is treated as untrusted input at all times. Log content never influences system behavior directly.

**Rationale:** Prompt injection attacks embed instructions in log fields (hostnames, user agents, DNS queries). A system that treats log content as trusted input can be manipulated by an attacker who controls network traffic.

**Required:**
- All log-derived data passed to the LLM is wrapped in explicit untrusted-data delimiters
- Evidence bundles are structured data, not free-form log text
- The LLM prompt template explicitly instructs the model that log content is untrusted

**Forbidden:**
- Passing raw log lines directly into LLM prompts
- Executing any string extracted from a log field as a command or query
- Treating LLM output as authoritative without human review

---

## Article VI — Prompt-Injection Resistance

**Principle:** The system is designed to resist prompt injection attacks embedded in network traffic.

**Rationale:** An attacker who controls DNS queries, HTTP user agents, or TLS SNI fields can embed LLM instructions in log data. This is a known and demonstrated attack class.

**Required:**
- Evidence bundles extract only typed, structured fields — not free-form strings
- String fields are truncated and escaped before inclusion in prompts
- The LLM prompt includes an explicit injection-resistance instruction
- Red-team tests include injection payloads in log fixtures

**Forbidden:**
- Including raw hostname, user-agent, or query strings in prompts without sanitization
- Trusting LLM output that references instructions found in log data

---

## Article VII — No Autonomous Destructive Actions

**Principle:** The system cannot autonomously delete, modify, block, or disrupt any resource.

**What can be automated safely:**
- Log ingestion and indexing
- Alert generation and routing
- Evidence bundle assembly
- LLM summarization (read-only)
- Dashboard refresh
- Log rotation and retention enforcement
- Backup execution (append-only)

**What requires human approval:**
- Any firewall or network change
- Any Wazuh rule or decoder change in production
- Any active response configuration
- Any log deletion or retention policy change
- Any LLM tool call that writes, modifies, or deletes

**Forbidden:**
- Automated IP blocking
- Automated firewall rule changes
- Any "auto-remediate if confidence > X%" logic

---

## Article VIII — Evidence-Backed Conclusions Only

**Principle:** Every LLM conclusion must cite the specific evidence (alert ID, log timestamp, field values) that supports it.

**Rationale:** Unsupported LLM conclusions are hallucinations. In a security context, acting on a hallucination can cause harm.

**Required:**
- LLM output schema includes a mandatory `evidence` array
- Each claim in the LLM response references at least one evidence item
- Evidence items include source log type, timestamp, and field values
- The LLM distinguishes `confirmed_fact` from `hypothesis` in its output

**Forbidden:**
- LLM responses without evidence citations
- Treating LLM hypotheses as confirmed facts
- Displaying LLM output without the evidence panel

---

## Article IX — Reproducible Infrastructure

**Principle:** The entire stack can be rebuilt from the repository with a single documented procedure.

**Required:**
- All configuration is in version control
- Secrets are injected via `.env` (gitignored) or a documented secret manager
- Docker images are pinned to specific versions
- `make up` brings the full stack online from a clean state

**Forbidden:**
- Manual configuration steps not documented in a runbook
- Unpinned Docker image tags (`latest`) in production compose files
- Secrets committed to the repository

---

## Article X — Test-First Detection Logic

**Principle:** No detection rule ships without a corresponding log fixture and regression test.

**Rationale:** Untested rules produce false positives, miss true positives, and erode operator trust. A rule without a test is a guess.

**Required:**
- Every decoder has a unit test with a sample log input and expected parsed fields
- Every rule has a fixture log that triggers it and a fixture log that does not
- `wazuh-logtest` is automated in CI
- Rule changes require passing all existing regression tests before merge

**Forbidden:**
- Merging a new rule without a corresponding test
- Disabling tests to make a rule pass
- Shipping rules based on intuition without empirical log samples

---

## Article XI — Least Privilege for All Service Accounts

**Principle:** Every service account has only the permissions required for its function.

**Required:**
- Wazuh API read-only account for LLM service
- Separate Wazuh admin account for operator use only
- Docker containers run as non-root where possible
- Zeek runs as a dedicated `zeek` user on the host

**Forbidden:**
- Sharing credentials between services
- Using admin credentials in automated pipelines
- Storing credentials in environment variables that are logged

---

## Article XII — Separation of Detection, Analysis, and Response

**Principle:** Detection (Zeek/Wazuh rules), analysis (LLM assistant), and response (human operator) are distinct layers with explicit interfaces.

**Required:**
- Detection layer produces structured alerts only
- Analysis layer consumes alerts and produces structured summaries only
- Response layer is always a human action
- Each layer has a documented API/interface

---

## Article XIII — Auditability of All Model Outputs

**Principle:** Every LLM prompt, response, evidence bundle, and tool call is logged with full fidelity.

**Required:**
- Audit log is append-only
- Audit log includes: timestamp, model, prompt hash, response hash, evidence bundle ID, tool calls attempted
- Audit log is queryable but not modifiable by the LLM

**Forbidden:**
- LLM calls without audit logging
- Modifying or deleting audit log entries

---

## Article XIV — Operational Simplicity Before Orchestration Complexity

**Principle:** Docker Compose is the default. Kubernetes is not introduced until Docker Compose is insufficient and the justification is documented in an ADR.

**Rationale:** Kubernetes adds significant operational complexity. For a home/SOHO lab, this complexity is rarely justified and often counterproductive.

**Promotion gate:** A documented ADR must exist before any Kubernetes work begins.

---

## Article XV — Explicit Promotion Gates

**Principle:** No phase of the project advances without passing its defined gate.

**Required:**
- Each gate has documented pass/fail criteria
- Gate evidence is stored in `/gates/`
- Gates are reviewed before merge to main

---

## Definitions

**Definition of Done:** A feature is done when it has passing tests, passing gate evidence, documentation, and has been reviewed by the relevant skill role.

**Definition of Unsafe:** An action is unsafe if it can modify, delete, or disrupt any system resource without explicit human approval, or if it sends raw log data outside the local network.
