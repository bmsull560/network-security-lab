# Gate Evidence: Decoder Correctness Gate

**Gate:** 07 — Decoder Correctness  
**Phase:** 4 — Custom Decoders and Rules  
**Date:** 2026-04-25  
**Reviewer:** Wazuh Decoder / Rule Engineer  
**Status:** PASS (static review; logtest pending live stack)

---

## What Was Tested

Reviewed `wazuh/decoders/zeek_decoders.xml` for correct syntax, field coverage, and constitution compliance.

## Evidence

| Check | Result | Notes |
|---|---|---|
| `xmllint --noout wazuh/decoders/zeek_decoders.xml` | PASS | No XML syntax errors |
| Root decoder uses `<prematch>` not `<program_name>` | PASS | Matches `"ts":` present in all Zeek JSON logs |
| All child decoders have `<parent>zeek</parent>` | PASS | Correct parent chain |
| DNS fields covered: query, rcode, qtype, flags | PASS | All fields present |
| Connection fields covered: conn_state, bytes, packets | PASS | All fields present |
| SSL fields covered: version, cipher, server_name, validation_status | PASS | All fields present |
| Software fields covered: type, name, version | PASS | All fields present |
| No decoder modifies or executes log content | PASS | Article V compliance |
| Rule IDs in reserved range 100900–101999 | PASS | All rules in range |
| Every rule has a corresponding fixture | PASS | Verified in tests/fixtures/ |
| `xmllint --noout wazuh/rules/zeek_rules.xml` | PASS | No XML syntax errors |
| MITRE ATT&CK IDs on threat rules | PASS | T1046 (scan), T1557 (MITM) |

## Fixtures Verified

| Fixture | Expected Rule | Status |
|---|---|---|
| `dns/dns-normal.json` | 100901 (level 5) | Fixture present |
| `dns/dns-nxdomain.json` | 100901 (level 5) | Fixture present |
| `dns/dns-long-query.json` | 100910 (level 7) | Fixture present |
| `dns/dns-mdns.json` | 100902 (level 0) | Fixture present |
| `conn/conn-rejected.json` | 100903 (level 7) | Fixture present |
| `conn/conn-established.json` | 100900 (level 0) | Fixture present |
| `ssl/ssl-self-signed.json` | 100906 (level 8) | Fixture present |
| `ssl/ssl-expired.json` | 100907 (level 12) | Fixture present |
| `ssl/ssl-valid.json` | 100900 (level 0) | Fixture present |

## Pending (requires live stack)

| Check | Status |
|---|---|
| `make test-rules` passes all fixtures | PENDING |
| Wazuh logtest confirms field extraction for each fixture | PENDING |

## Reviewer Sign-Off

**Reviewer:** Wazuh Decoder / Rule Engineer  
**Role:** Wazuh Decoder / Rule Engineer  
**Date:** 2026-04-25  
**Decision:** PASS (static review)  
**Notes:** XML syntax valid. Field coverage complete. Live logtest required before Phase 5 promotion.
