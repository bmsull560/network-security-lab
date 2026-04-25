#!/usr/bin/env bash
# push-to-github.sh — Create the GitHub repo and push all commits
#
# Usage:
#   GITHUB_TOKEN=ghp_xxx bash scripts/push-to-github.sh
#
# Requirements:
#   - A GitHub personal access token with 'repo' scope
#   - curl

set -euo pipefail

GITHUB_USER="bmsull560"
REPO_NAME="network-security-lab"
TOKEN="${GITHUB_TOKEN:?GITHUB_TOKEN environment variable is required}"

echo "→ Creating GitHub repository ${GITHUB_USER}/${REPO_NAME}..."
curl -sf -X POST \
  -H "Authorization: token ${TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/user/repos \
  -d "{
    \"name\": \"${REPO_NAME}\",
    \"description\": \"Home/SOHO network observability: Zeek + Wazuh + local LLM analyst\",
    \"private\": false,
    \"auto_init\": false,
    \"has_issues\": true,
    \"has_projects\": false,
    \"has_wiki\": false
  }" | python3 -c "import sys,json; d=json.load(sys.stdin); print('  Created:', d['html_url'])" 2>/dev/null \
  || echo "  (repo may already exist — continuing)"

echo "→ Setting remote origin..."
git remote remove origin 2>/dev/null || true
git remote add origin "https://${GITHUB_USER}:${TOKEN}@github.com/${GITHUB_USER}/${REPO_NAME}.git"

echo "→ Pushing all commits to main..."
git push -u origin main

echo "→ Enabling branch protection on main..."
curl -sf -X PUT \
  -H "Authorization: token ${TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/${GITHUB_USER}/${REPO_NAME}/branches/main/protection" \
  -d '{
    "required_status_checks": null,
    "enforce_admins": false,
    "required_pull_request_reviews": {
      "required_approving_review_count": 1
    },
    "restrictions": null,
    "allow_force_pushes": false,
    "allow_deletions": false
  }' > /dev/null && echo "  Branch protection enabled" || echo "  (branch protection requires admin — set manually if needed)"

echo ""
echo "✓ Repository live at: https://github.com/${GITHUB_USER}/${REPO_NAME}"
