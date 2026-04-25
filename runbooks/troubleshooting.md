# Runbook: Troubleshooting

## Zeek

### No logs in /opt/zeek/logs/current/

```bash
sudo /opt/zeek/bin/zeekctl status
# If not running:
sudo /opt/zeek/bin/zeekctl deploy

# Check for errors
sudo /opt/zeek/bin/zeekctl diag
```

**Common causes:**
- Wrong interface in `node.cfg` — verify with `ip link show`
- No traffic on capture interface — verify mirror port on switch
- Zeek crashed — check `/opt/zeek/logs/stats/` for crash logs

### Logs are TSV, not JSON

```bash
grep "json-logs" /opt/zeek/share/zeek/site/local.zeek
# Should show: @load policy/tuning/json-logs.zeek
# If missing, add it and run: sudo zeekctl deploy
```

### conn.log only shows sensor host traffic

Mirror port is not configured correctly. See `runbooks/sensor-placement.md`.

---

## Wazuh Stack

### Container not starting

```bash
make logs s=wazuh-indexer   # check indexer logs
make logs s=wazuh-manager   # check manager logs
```

**Common causes:**
- Indexer OOM: increase Docker memory limit or host RAM
- Volume permission error: `docker volume rm wazuh-indexer-data && make up`
- Missing certs: run `make certs-generate`
- Missing `.env`: `cp docker/.env.example docker/.env` and fill in passwords

### Dashboard not accessible

```bash
make status   # check all containers are healthy
make logs s=wazuh-dashboard
```

If dashboard is healthy but unreachable, check port binding:
```bash
docker port wazuh-dashboard
# Should show: 5601/tcp -> 127.0.0.1:443
```

### Agent not connecting

```bash
sudo systemctl status wazuh-agent
sudo tail -50 /var/ossec/logs/ossec.log
```

**Common causes:**
- Wrong manager IP in `ossec.conf`
- Port 1514 not reachable (check `docker/.env` port binding)
- Registration password mismatch

### Events not appearing in dashboard

```bash
# Check agent is shipping logs
sudo tail -f /var/ossec/logs/ossec.log | grep zeek

# Check decoder is parsing correctly (requires Wazuh API)
source docker/.env
curl -sk -u "${WAZUH_API_USERNAME}:${WAZUH_API_PASSWORD}" \
  -X PUT https://localhost:55000/logtest \
  -H "Content-Type: application/json" \
  -d "{\"event\": $(cat tests/fixtures/dns/dns-normal.json | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))'), \"log_format\": \"json\", \"location\": \"zeek\"}" | jq .
```

---

## Rule Tests

### make test-rules fails

```bash
# Run with verbose output
bash tests/rules/run-all.sh 2>&1 | head -50

# Check a specific fixture manually
source docker/.env
curl -sk -u "${WAZUH_API_USERNAME}:${WAZUH_API_PASSWORD}" \
  -X PUT https://localhost:55000/logtest \
  -H "Content-Type: application/json" \
  -d "{\"event\": $(cat tests/fixtures/dns/dns-normal.json | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))'), \"log_format\": \"json\", \"location\": \"zeek\"}" | jq '.data.output.rule'
```

### xmllint fails on decoder/rule XML

```bash
xmllint --noout wazuh/decoders/zeek_decoders.xml
xmllint --noout wazuh/rules/zeek_rules.xml
# Fix any reported errors before deploying
```

---

## Certificates

### Certificate expired or mismatched

```bash
# Regenerate dev certs
make certs-generate
make down && make up
```

For production, replace with proper PKI certificates.
