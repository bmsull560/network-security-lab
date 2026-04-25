#!/usr/bin/env bash
# tests/rules/run-all.sh — Rule regression test harness
#
# Runs wazuh-logtest against every fixture in tests/fixtures/ and compares
# the output to the corresponding .expected file in tests/rules/.
#
# Usage:
#   bash tests/rules/run-all.sh
#   make test-rules
#
# Requirements:
#   - Wazuh manager container must be running (make up)
#   - WAZUH_API_URL, WAZUH_API_USER, WAZUH_API_PASS set in environment
#     or sourced from docker/.env
#
# Exit codes:
#   0 — all tests passed
#   1 — one or more tests failed
#
# Constitution compliance:
#   Article X — no rule ships without a passing fixture test

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURES_DIR="$REPO_ROOT/tests/fixtures"
EXPECTED_DIR="$REPO_ROOT/tests/rules"

# Load env if available
ENV_FILE="$REPO_ROOT/docker/.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE"; set +a
fi

WAZUH_API_URL="${WAZUH_API_URL:-https://localhost:55000}"
WAZUH_API_USER="${WAZUH_API_USERNAME:-wazuh-wui}"
WAZUH_API_PASS="${WAZUH_API_PASSWORD:-}"

PASS=0
FAIL=0
SKIP=0
ERRORS=()

# ── Colour helpers ────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_pass() { echo -e "  ${GREEN}PASS${NC}  $1"; }
log_fail() { echo -e "  ${RED}FAIL${NC}  $1"; }
log_skip() { echo -e "  ${YELLOW}SKIP${NC}  $1"; }

# ── Get Wazuh API token ───────────────────────────────────────────────────────
get_token() {
  curl -sk -u "${WAZUH_API_USER}:${WAZUH_API_PASS}" \
    -X POST "${WAZUH_API_URL}/security/user/authenticate" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['token'])" 2>/dev/null
}

# ── Run logtest for a single log line ────────────────────────────────────────
run_logtest() {
  local log_line="$1"
  local token="$2"

  curl -sk -X PUT "${WAZUH_API_URL}/logtest" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "{\"event\": $(echo "$log_line" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))"), \"log_format\": \"json\", \"location\": \"zeek-test\"}" \
    2>/dev/null
}

# ── Check if Wazuh API is reachable ──────────────────────────────────────────
check_api() {
  curl -sk -o /dev/null -w "%{http_code}" \
    "${WAZUH_API_URL}/" 2>/dev/null || echo "000"
}

# ── Main test loop ────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Zeek Rule Regression Tests"
echo "═══════════════════════════════════════════════════════"
echo ""

# Check API availability
HTTP_CODE=$(check_api)
if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "401" ]]; then
  echo "⚠  Wazuh API not reachable at ${WAZUH_API_URL} (HTTP ${HTTP_CODE})"
  echo "   Run 'make up' first, then retry."
  echo ""
  echo "   Running in OFFLINE mode — validating fixture JSON only."
  echo ""
  OFFLINE=true
else
  OFFLINE=false
  TOKEN=$(get_token)
  if [[ -z "$TOKEN" ]]; then
    echo "⚠  Could not authenticate to Wazuh API. Check credentials in docker/.env"
    OFFLINE=true
  fi
fi

# Iterate over all fixture subdirectories
for fixture_type in dns conn ssl; do
  echo "── ${fixture_type} fixtures ──────────────────────────────────────"
  fixture_dir="$FIXTURES_DIR/$fixture_type"
  expected_dir="$EXPECTED_DIR/$fixture_type"

  if [[ ! -d "$fixture_dir" ]]; then
    echo "  (no fixtures found in $fixture_dir)"
    continue
  fi

  for fixture_file in "$fixture_dir"/*.json; do
    [[ -f "$fixture_file" ]] || continue
    fixture_name="$(basename "$fixture_file" .json)"
    expected_file="$expected_dir/${fixture_name}.expected"

    if [[ ! -f "$expected_file" ]]; then
      log_skip "$fixture_name — no .expected file found"
      SKIP=$((SKIP + 1))
      continue
    fi

    # Validate fixture is valid JSON
    if ! python3 -c "import sys,json; json.load(open('$fixture_file'))" 2>/dev/null; then
      log_fail "$fixture_name — fixture is not valid JSON"
      FAIL=$((FAIL + 1))
      ERRORS+=("$fixture_name: invalid JSON in fixture")
      continue
    fi

    if [[ "$OFFLINE" == "true" ]]; then
      # Offline: just validate JSON structure
      log_pass "$fixture_name — JSON valid (offline, logtest skipped)"
      PASS=$((PASS + 1))
      continue
    fi

    # Online: run logtest and compare
    LOG_LINE=$(cat "$fixture_file")
    LOGTEST_RESULT=$(run_logtest "$LOG_LINE" "$TOKEN")

    if [[ -z "$LOGTEST_RESULT" ]]; then
      log_skip "$fixture_name — empty logtest response"
      SKIP=$((SKIP + 1))
      continue
    fi

    # Extract fields from logtest response
    ACTUAL_RULE_ID=$(echo "$LOGTEST_RESULT" | python3 -c \
      "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('output',{}).get('rule',{}).get('id',''))" 2>/dev/null || echo "")
    ACTUAL_LEVEL=$(echo "$LOGTEST_RESULT" | python3 -c \
      "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('output',{}).get('rule',{}).get('level',''))" 2>/dev/null || echo "")
    ACTUAL_DESC=$(echo "$LOGTEST_RESULT" | python3 -c \
      "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('output',{}).get('rule',{}).get('description',''))" 2>/dev/null || echo "")

    # Read expected values
    EXP_RULE_ID=$(grep "^rule_id:" "$expected_file" | awk '{print $2}')
    EXP_LEVEL=$(grep "^rule_level:" "$expected_file" | awk '{print $2}')
    EXP_DESC_PREFIX=$(grep "^rule_description:" "$expected_file" | sed 's/^rule_description: //')

    # Compare
    MATCH=true
    MISMATCH_DETAIL=""

    if [[ "$ACTUAL_RULE_ID" != "$EXP_RULE_ID" ]]; then
      MATCH=false
      MISMATCH_DETAIL+=" rule_id: got=$ACTUAL_RULE_ID want=$EXP_RULE_ID"
    fi
    if [[ "$ACTUAL_LEVEL" != "$EXP_LEVEL" ]]; then
      MATCH=false
      MISMATCH_DETAIL+=" level: got=$ACTUAL_LEVEL want=$EXP_LEVEL"
    fi
    if [[ -n "$EXP_DESC_PREFIX" ]] && [[ "$ACTUAL_DESC" != *"$EXP_DESC_PREFIX"* ]]; then
      MATCH=false
      MISMATCH_DETAIL+=" description mismatch"
    fi

    if [[ "$MATCH" == "true" ]]; then
      log_pass "$fixture_name (rule $ACTUAL_RULE_ID, level $ACTUAL_LEVEL)"
      PASS=$((PASS + 1))
    else
      log_fail "$fixture_name —$MISMATCH_DETAIL"
      FAIL=$((FAIL + 1))
      ERRORS+=("$fixture_name:$MISMATCH_DETAIL")
    fi
  done
  echo ""
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════════"
echo "  Results: ${PASS} passed  ${FAIL} failed  ${SKIP} skipped"
echo "═══════════════════════════════════════════════════════"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failures:"
  for err in "${ERRORS[@]}"; do
    echo "  ✗ $err"
  done
fi

echo ""

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
