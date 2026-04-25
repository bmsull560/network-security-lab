# Runbook: Adding or Modifying Detection Rules

**Constitution compliance:** Article X — no rule ships without a passing fixture test.

## Workflow

```
1. Write the rule in wazuh/rules/zeek_rules.xml
2. Write a fixture log in tests/fixtures/<type>/
3. Write the expected output in tests/rules/<type>/
4. Run make test-rules — must pass
5. Deploy to manager (docker restart wazuh-manager)
6. Run simulation to validate in live stack
7. Commit with gate evidence
```

## Step 1 — Write the Rule

Edit `wazuh/rules/zeek_rules.xml`. Use rule IDs in the range **100900–101999**.

```xml
<rule id="100920" level="8">
  <if_sid>100900</if_sid>
  <field name="dns_query">\.onion$</field>
  <description>Zeek: DNS query for .onion domain from $(srcip) — Tor usage detected</description>
  <group>zeek_dns,zeek_suspicious,</group>
  <mitre>
    <id>T1090.003</id>
  </mitre>
</rule>
```

**Rule ID allocation:**

| Range | Use |
|---|---|
| 100900–100909 | Base and DNS rules |
| 100910–100919 | DNS anomaly rules |
| 100920–100929 | DNS threat rules |
| 100930–100949 | Connection / port scan rules |
| 100950–100969 | SSL/TLS rules |
| 100970–100999 | Reserved |
| 101000+ | Future use |

## Step 2 — Write a Fixture

Create a realistic Zeek JSON log in `tests/fixtures/<type>/`:

```bash
# Example: tests/fixtures/dns/dns-onion.json
{
  "ts": 1745539600.0,
  "uid": "XYZ123",
  "id.orig_h": "192.168.1.42",
  "id.orig_p": 54500,
  "id.resp_h": "8.8.8.8",
  "id.resp_p": 53,
  "proto": "udp",
  "query": "facebookwkhpilnemxj7asber7cybef5.onion",
  "rcode_name": "NXDOMAIN",
  "RD": true, "RA": true, "AA": false, "TC": false,
  "rejected": false
}
```

Also write a **benign fixture** that should NOT trigger the rule.

## Step 3 — Write Expected Output

Create `tests/rules/<type>/<fixture-name>.expected`:

```
rule_id: 100920
rule_level: 8
rule_description: Zeek: DNS query for .onion domain
decoder_name: zeek
```

## Step 4 — Run Tests

```bash
make test-rules
```

All existing fixtures must still pass. The new fixture must produce the expected output.

If the Wazuh API is not running, tests run in offline mode (JSON validation only). Start the stack first for full logtest validation:

```bash
make up
make test-rules
```

## Step 5 — Deploy

```bash
# Rules are mounted into the manager container — restart to reload
docker restart wazuh-manager

# Verify the rule is loaded
curl -sk -u wazuh-wui:$WAZUH_API_PASSWORD \
  https://localhost:55000/rules?rule_ids=100920 | jq .
```

## Step 6 — Validate Live

Run a simulation that should trigger the new rule and verify the alert appears in the dashboard.

## Step 7 — Commit

```bash
git add wazuh/rules/zeek_rules.xml \
        tests/fixtures/dns/dns-onion.json \
        tests/rules/dns/dns-onion.expected
git commit -m "detect: add rule 100920 for .onion DNS queries

Detects DNS queries for .onion domains which indicate Tor usage.
Fixture: tests/fixtures/dns/dns-onion.json
MITRE: T1090.003"
```

## Modifying an Existing Rule

1. Make the change in `zeek_rules.xml`
2. Run `make test-rules` — all existing fixtures must still pass
3. If the change affects expected output, update the `.expected` file
4. Deploy and validate as above

## Removing a Rule

1. Remove the rule from `zeek_rules.xml`
2. Remove the corresponding fixture and `.expected` file
3. Run `make test-rules` to confirm no references remain
4. Document the removal in an ADR if the rule was significant
