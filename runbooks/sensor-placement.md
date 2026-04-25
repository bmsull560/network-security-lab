# Runbook: Sensor Placement and Mirror Port Configuration

## Goal

Configure your managed switch to mirror all network traffic to the Zeek sensor NIC, so Zeek sees traffic between all devices on your network — not just traffic to/from the sensor host.

## Network Topology

```
Internet
    │
  Router/Modem
    │
  Managed Switch  ← configure SPAN/mirror port here
    ├── Port 1: Sensor host eth1 (capture NIC — receives mirrored traffic)
    ├── Port 2: Sensor host eth0 (management NIC)
    ├── Port 3: Desktop
    ├── Port 4: IoT device
    └── Port N: Other devices
```

## Sensor Host NIC Requirements

| NIC | Role | IP Required? | Notes |
|---|---|---|---|
| `eth0` | Management | Yes | SSH, Docker, Wazuh agent communication |
| `eth1` | Capture | No | Promiscuous mode; receives mirrored traffic |

The capture NIC (`eth1`) does not need an IP address. Zeek reads directly from the interface.

## Switch Configuration (Generic)

The exact steps depend on your switch vendor. The concept is the same:

1. **Select a mirror source** — the port(s) or VLAN(s) whose traffic you want to capture
2. **Select a mirror destination** — the port connected to `eth1` on the sensor host
3. **Enable the mirror session**

### Example: Ubiquiti UniFi

1. Log into UniFi Network Controller
2. Go to **Settings → Networks → Port Mirroring**
3. Set **Mirror Port** to the port connected to `eth1`
4. Set **Mirror Source** to all other ports (or the uplink port for all traffic)
5. Save

### Example: Cisco IOS

```
monitor session 1 source interface GigabitEthernet0/1 - 0/8 both
monitor session 1 destination interface GigabitEthernet0/9
```

### Example: TP-Link Smart Switch

1. Log into switch web UI
2. Go to **Switching → Mirroring**
3. Set **Mirroring Port** to the port connected to `eth1`
4. Check all other ports as **Mirrored Ports**
5. Enable and save

## Validate Mirror Port is Working

After configuring the mirror port, verify Zeek sees traffic from multiple hosts:

```bash
# Should show traffic from multiple source IPs, not just the sensor host
sudo tcpdump -i eth1 -n -c 20 2>/dev/null | awk '{print $3}' | sort -u

# Or with Zeek running:
tail -f /opt/zeek/logs/current/conn.log | jq '."id.orig_h"' | sort -u
```

If you only see the sensor host's own IP, the mirror port is not configured correctly.

## Common Issues

| Symptom | Likely Cause | Fix |
|---|---|---|
| Only sensor host traffic in conn.log | Mirror port not configured | Configure SPAN on switch |
| No traffic at all | Wrong interface in node.cfg | Check `ZEEK_INTERFACE` matches capture NIC |
| Partial traffic | VLAN tagging on mirror port | Disable VLAN tagging on mirror destination port |
| High packet drop rate | NIC buffer overflow | Use a faster NIC; reduce mirror source ports |

## Promiscuous Mode

Zeek automatically puts the capture interface into promiscuous mode. This is expected and required. You can verify:

```bash
ip link show eth1 | grep PROMISC
# Should show: PROMISC in the flags
```

## Single-NIC Setup (No Mirror Port)

If you only have one NIC or no managed switch, Zeek can still capture traffic to/from the sensor host itself. This is useful for testing but provides limited visibility.

Set `ZEEK_INTERFACE` to your single NIC (e.g., `eth0`) and accept that you will only see traffic involving the sensor host.
