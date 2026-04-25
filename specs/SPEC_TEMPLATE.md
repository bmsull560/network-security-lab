# Spec: [Feature Name]

**Spec ID:** [NNN]  
**Phase:** [N — Name]  
**Status:** Draft | Review | Approved | Implemented | Tested  
**Author:** [Role]  
**Date:** [YYYY-MM-DD]

---

## Problem Statement

[What problem does this feature solve? Why does it need to exist?]

## Operator Story

As a [home network operator / security analyst], I want to [action] so that [outcome].

## Security Story

As an attacker, I could [threat] unless [mitigation]. This feature mitigates this by [approach].

## Scope

[What is included in this spec.]

## Non-Goals

[What is explicitly excluded. Be specific.]

## Architecture Impact

[How does this change the system architecture? Which components are affected?]

## Data Flow

[Describe the data path from source to destination. Include log format, transport, and storage.]

## Inputs

[What data, configuration, or events does this feature consume?]

## Outputs

[What does this feature produce? Alerts, logs, API responses, files?]

## Dependencies

[Other specs, services, or external systems this feature depends on.]

## Detection Logic

[Detection hypothesis, log fields used, threshold or pattern, expected alert. State "N/A" if not a detection feature.]

## LLM Involvement

[What data is passed, in what form, expected output. State "None" if not applicable.]

## Prompt Injection Risk Assessment

[What log fields are in LLM context? What sanitization is applied? State "N/A" if no LLM involvement.]

## Privacy Impact

[What personal or sensitive data does this feature handle? How is it protected?]

## Failure Modes

| Failure | Impact | Mitigation |
|---|---|---|
| [failure] | [impact] | [mitigation] |

## Test Cases

| ID | Scenario | Input Fixture | Expected Output | Pass Criteria |
|---|---|---|---|---|
| T-001 | [scenario] | [fixture file] | [expected] | [criteria] |

## Acceptance Criteria

- [ ] [Criterion 1]
- [ ] [Criterion 2]

## Rollback Plan

[How is this feature disabled or reverted if it causes problems?]

## Promotion Gate Checklist

- [ ] All test cases pass
- [ ] Gate evidence documented in `/gates/`
- [ ] ADR written if architecture changed
- [ ] Documentation updated
- [ ] Reviewed by relevant skill role
- [ ] No secrets in committed files
- [ ] Constitution compliance verified
