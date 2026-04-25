# Runbook: Full Stack Deployment

**Phase:** 1–3  
**Time:** ~30 minutes on a clean Ubuntu 24.04 host

## Prerequisites

- Ubuntu 24.04 LTS (fresh install recommended)
- 8 GB RAM minimum (4 GB for Wazuh indexer)
- 50 GB disk
- Docker Engine 24+ and Docker Compose v2
- Two NICs: `eth0` (management) and `eth1` (capture), or a single NIC with mirror port
- Internet access for package downloads
- A managed switch with SPAN/mirror port capability (see `runbooks/sensor-placement.md`)

## Step 1 — Clone the Repository

```bash
git clone https://github.com/bmsull560/network-security-lab.git
cd network-security-lab
```

## Step 2 — Install Docker

```bash
curl -fsSL https://get.docker.com | sudo bash
sudo usermod -aG docker $USER
newgrp docker
docker --version   # verify: Docker version 24+
```

## Step 3 — Configure Environment

```bash
cp docker/.env.example docker/.env
```

Edit `docker/.env` and set **all** of the following:

| Variable | Description |
|---|---|
| `INDEXER_PASSWORD` | Strong password for OpenSearch admin |
| `WAZUH_API_PASSWORD` | Strong password for Wazuh API |
| `DASHBOARD_PASSWORD` | Strong password for dashboard login |
| `WAZUH_REGISTRATION_PASSWORD` | Password agents use to enroll |
| `LOCAL_NETWORK` | Your LAN subnet (e.g. `192.168.1.0/24`) |

⚠ Never commit `docker/.env`. It is gitignored.

## Step 4 — Generate TLS Certificates (Development)

```bash
make certs-generate
```

This generates self-signed certificates in `docker/certs/`. For production, replace with certificates from your PKI or Let's Encrypt.

## Step 5 — Start the Wazuh Stack

```bash
make up
```

Wait for all containers to become healthy (~2–3 minutes):

```bash
make status
# All three containers should show "healthy"
```

## Step 6 — Verify Dashboard Access

Open a browser to `https://localhost` (accept the self-signed cert warning).

Default credentials are in `docker/.env` (`DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD`).

## Step 7 — Install Zeek on the Sensor Host

```bash
sudo ZEEK_INTERFACE=eth1 ZEEK_NETWORK=192.168.1.0/24 bash scripts/install-zeek.sh
```

Replace `eth1` with your capture interface and `192.168.1.0/24` with your LAN subnet.

Verify:
```bash
sudo /opt/zeek/bin/zeekctl status
ls /opt/zeek/logs/current/
tail -f /opt/zeek/logs/current/conn.log | jq .
```

## Step 8 — Install and Enroll the Wazuh Agent

```bash
sudo WAZUH_MANAGER_IP=127.0.0.1 bash scripts/install-agent.sh
```

If the Wazuh manager is on a different host, replace `127.0.0.1` with its IP.

Verify the agent appears in the Wazuh dashboard under **Agents**.

## Step 9 — Deploy Custom Decoders and Rules

The decoders and rules in `wazuh/decoders/` and `wazuh/rules/` are mounted into the manager container automatically via the Docker Compose volume mount.

Restart the manager to apply:
```bash
docker restart wazuh-manager
```

## Step 10 — Validate End-to-End Pipeline

Run the simulation scripts and verify alerts appear in the dashboard:

```bash
bash scripts/simulate/dns-queries.sh
bash scripts/simulate/ssl-badcert.sh
bash scripts/simulate/port-scan.sh
```

In the Wazuh dashboard:
1. Navigate to **Threat Intelligence → Threat Hunting → Events**
2. Filter by `rule.id is one of 100901, 100903, 100904, 100906, 100907, 100910`
3. Confirm alerts appear within 30 seconds of running each script

## Step 11 — Run Regression Tests

```bash
make test-rules
```

All fixtures should pass. If any fail, check `runbooks/troubleshooting.md`.

## Ongoing Operations

| Task | Command |
|---|---|
| Start stack | `make up` |
| Stop stack | `make down` |
| View logs | `make logs` |
| Check health | `make status` |
| Run tests | `make test-rules` |
| Backup | `make backup` |
| Update rules | See `runbooks/rule-update.md` |
