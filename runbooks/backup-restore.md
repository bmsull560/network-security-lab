# Runbook: Backup and Restore

## Backup

```bash
make backup
# or
bash scripts/backup.sh [OPTIONAL_OUTPUT_DIR]
```

Backups are written to `backups/YYYY-MM-DD/` and contain:

| Path | Contents |
|---|---|
| `config/ossec-etc/` | Wazuh manager `/var/ossec/etc/` |
| `config/api-config/` | Wazuh API configuration |
| `config/custom-wazuh/` | Custom decoders and rules (also in git) |
| `MANIFEST.txt` | Backup metadata and restore reference |

The Wazuh indexer snapshot is stored inside the `wazuh-indexer-data` Docker volume at `/var/lib/wazuh-indexer/snapshots/`.

Add `backups/` to `.gitignore` — backup archives should not be committed.

## Restore Procedure

### 1. Start a clean stack

```bash
make down
docker volume rm $(docker volume ls -q | grep network-security-lab) 2>/dev/null || true
make up
# Wait for all containers to be healthy
make status
```

### 2. Restore manager configuration

```bash
BACKUP_DIR=backups/YYYY-MM-DD   # set to your backup date

docker cp "$BACKUP_DIR/config/ossec-etc/." wazuh-manager:/var/ossec/etc/
docker cp "$BACKUP_DIR/config/api-config/." wazuh-manager:/var/ossec/api/configuration/
docker restart wazuh-manager
```

### 3. Restore indexer snapshot

```bash
# Load env
source docker/.env

# List available snapshots
curl -sk -u "${INDEXER_USERNAME}:${INDEXER_PASSWORD}" \
  https://localhost:9200/_snapshot/wazuh-backup/_all | jq '.snapshots[].snapshot'

# Restore a specific snapshot (replace SNAPSHOT_NAME)
curl -sk -u "${INDEXER_USERNAME}:${INDEXER_PASSWORD}" \
  -X POST "https://localhost:9200/_snapshot/wazuh-backup/SNAPSHOT_NAME/_restore?wait_for_completion=true" \
  -H "Content-Type: application/json" \
  -d '{"indices": "wazuh-*", "ignore_unavailable": true}'
```

### 4. Validate

```bash
# Check indexer health
curl -sk -u "${INDEXER_USERNAME}:${INDEXER_PASSWORD}" \
  https://localhost:9200/_cluster/health | jq .status

# Check alert count
curl -sk -u "${INDEXER_USERNAME}:${INDEXER_PASSWORD}" \
  https://localhost:9200/wazuh-alerts-*/_count | jq .count

# Open dashboard and verify alerts are present
# https://localhost
```

## Backup Schedule Recommendation

| Frequency | Method |
|---|---|
| Daily | `make backup` via cron |
| Before any rule change | `make backup` manually |
| Before stack upgrade | `make backup` manually |

Example cron entry (daily at 02:00):
```
0 2 * * * cd /path/to/network-security-lab && make backup >> /var/log/nsm-backup.log 2>&1
```
