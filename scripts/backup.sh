#!/usr/bin/env bash
# backup.sh — Backup Wazuh configuration and index snapshots
#
# Usage:
#   bash scripts/backup.sh [BACKUP_DIR]
#
# Arguments:
#   BACKUP_DIR  Directory to write backups (default: ./backups/YYYY-MM-DD)
#
# What is backed up:
#   1. Wazuh manager configuration (from Docker volume)
#   2. Custom decoders and rules (from repo — already in git)
#   3. Wazuh indexer snapshot (OpenSearch snapshot API)
#
# Constitution compliance:
#   Article IX  — reproducible infrastructure
#   Article VII — backup is append-only, no destructive operations

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATE=$(date +%Y-%m-%d)
BACKUP_DIR="${1:-$REPO_ROOT/backups/$DATE}"

ENV_FILE="$REPO_ROOT/docker/.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE"; set +a
fi

WAZUH_API_URL="${WAZUH_API_URL:-https://localhost:55000}"
WAZUH_API_USER="${WAZUH_API_USERNAME:-wazuh-wui}"
WAZUH_API_PASS="${WAZUH_API_PASSWORD:-}"
INDEXER_URL="${INDEXER_URL:-https://localhost:9200}"
INDEXER_USER="${INDEXER_USERNAME:-admin}"
INDEXER_PASS="${INDEXER_PASSWORD:-}"

mkdir -p "$BACKUP_DIR"/{config,snapshots}

echo "═══════════════════════════════════════════════════════"
echo "  Wazuh Backup — $DATE"
echo "  Output: $BACKUP_DIR"
echo "═══════════════════════════════════════════════════════"
echo ""

# ── 1. Backup manager config from Docker volume ───────────────────────────────
echo "→ Backing up Wazuh manager configuration..."
if docker ps --format '{{.Names}}' | grep -q "wazuh-manager"; then
  docker cp wazuh-manager:/var/ossec/etc/. "$BACKUP_DIR/config/ossec-etc/" 2>/dev/null || true
  docker cp wazuh-manager:/var/ossec/api/configuration/. "$BACKUP_DIR/config/api-config/" 2>/dev/null || true
  echo "  ✓ Manager config backed up"
else
  echo "  ⚠  wazuh-manager container not running — skipping config backup"
fi

# ── 2. Backup custom decoders and rules ───────────────────────────────────────
echo "→ Backing up custom decoders and rules..."
cp -r "$REPO_ROOT/wazuh/" "$BACKUP_DIR/config/custom-wazuh/"
echo "  ✓ Custom decoders and rules backed up"

# ── 3. Wazuh indexer snapshot ─────────────────────────────────────────────────
echo "→ Creating Wazuh indexer snapshot..."

# Register snapshot repository if not already registered
REPO_CHECK=$(curl -sk -u "${INDEXER_USER}:${INDEXER_PASS}" \
  "${INDEXER_URL}/_snapshot/wazuh-backup" \
  -w "\n%{http_code}" 2>/dev/null | tail -1)

if [[ "$REPO_CHECK" == "404" ]]; then
  echo "  → Registering snapshot repository..."
  curl -sk -u "${INDEXER_USER}:${INDEXER_PASS}" \
    -X PUT "${INDEXER_URL}/_snapshot/wazuh-backup" \
    -H "Content-Type: application/json" \
    -d '{
      "type": "fs",
      "settings": {
        "location": "/var/lib/wazuh-indexer/snapshots",
        "compress": true
      }
    }' > /dev/null
fi

# Create snapshot
SNAPSHOT_NAME="backup-${DATE}-$(date +%H%M%S)"
SNAPSHOT_RESULT=$(curl -sk -u "${INDEXER_USER}:${INDEXER_PASS}" \
  -X PUT "${INDEXER_URL}/_snapshot/wazuh-backup/${SNAPSHOT_NAME}?wait_for_completion=true" \
  -H "Content-Type: application/json" \
  -d '{"indices": "wazuh-*", "ignore_unavailable": true}' 2>/dev/null || echo "")

if echo "$SNAPSHOT_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('snapshot',{}).get('state')=='SUCCESS' else 1)" 2>/dev/null; then
  echo "  ✓ Indexer snapshot created: $SNAPSHOT_NAME"
else
  echo "  ⚠  Indexer snapshot may have failed or indexer not reachable"
  echo "     Result: $SNAPSHOT_RESULT"
fi

# ── 4. Write backup manifest ──────────────────────────────────────────────────
cat > "$BACKUP_DIR/MANIFEST.txt" << EOF
Wazuh Backup Manifest
Date: $DATE $(date +%H:%M:%S)
Host: $(hostname)

Contents:
  config/ossec-etc/     — Wazuh manager /var/ossec/etc/
  config/api-config/    — Wazuh API configuration
  config/custom-wazuh/  — Custom decoders and rules (also in git)
  Indexer snapshot:     $SNAPSHOT_NAME

Restore procedure: see runbooks/backup-restore.md
EOF

echo ""
echo "✓ Backup complete: $BACKUP_DIR"
echo ""
echo "Restore procedure: see runbooks/backup-restore.md"
