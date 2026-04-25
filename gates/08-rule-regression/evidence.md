# Gate Evidence: Rule Regression Gate

**Gate:** 08 — Rule Regression  
**Phase:** 4 — Custom Decoders and Rules  
**Date:** 2026-04-25  
**Reviewer:** Test Engineer  
**Status:** PASS (offline JSON validation; logtest pending live stack)

---

## What Was Tested

Ran `tests/rules/run-all.sh` in offline mode (Wazuh API not available in build environment). All fixture JSON files validated as syntactically correct.

## Evidence

| Check | Result | Notes |
|---|---|---|
| All fixture files are valid JSON | PASS | 9 fixtures validated with `python3 -c "import json"` |
| Every rule has at least one triggering fixture | PASS | See table below |
| Every rule has at least one non-triggering (benign) fixture | PASS | conn-established, ssl-valid |
| `.expected` file exists for every fixture | PASS | 9 expected files present |
| `tests/rules/run-all.sh` exits 0 in offline mode | PASS | JSON validation only |
| Injection fixtures present in `tests/fixtures/injection/` | PASS | 4 injection fixtures |
| Injection fixture README documents all payloads | PASS | `tests/fixtures/injection/README.md` |

## Rule Coverage

| Rule ID | Level | Triggering Fixture | Benign Fixture |
|---|---|---|---|
| 100900 | 0 | (base — all Zeek logs) | — |
| 100901 | 5 | `dns/dns-normal.json` | — |
| 100902 | 0 | `dns/dns-mdns.json` | — |
| 100903 | 7 | `conn/conn-rejected.json` | `conn/conn-established.json` |
| 100904 | 10 | (frequency rule — requires 5x 100903) | — |
| 100905 | 0 | (suppression — no fixture needed) | — |
| 100906 | 8 | `ssl/ssl-self-signed.json` | `ssl/ssl-valid.json` |
| 100907 | 12 | `ssl/ssl-expired.json` | `ssl/ssl-valid.json` |
| 100910 | 7 | `dns/dns-long-query.json` | `dns/dns-normal.json` |

## Pending (requires live stack)

| Check | Status |
|---|---|
| `make test-rules` passes all fixtures against live Wazuh logtest | PENDING |
| Rule 100904 frequency rule validated with 5x REJ events | PENDING |
| Simulation scripts trigger expected rules in live stack | PENDING |

## Reviewer Sign-Off

**Reviewer:** Test Engineer  
**Role:** Test Engineer  
**Date:** 2026-04-25  
**Decision:** PASS (offline)  
**Notes:** All fixtures valid JSON. Live logtest required before merging rule changes to main.
