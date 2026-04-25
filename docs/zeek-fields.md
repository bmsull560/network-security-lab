# Zeek Log Field Reference

Fields used by `zeek_decoders.xml` and referenced in `zeek_rules.xml`.

## conn.log — Connection Summary

| Zeek Field | Wazuh Decoder Field | Type | Description |
|---|---|---|---|
| `id.orig_h` | `srcip` | IP | Originating host IP |
| `id.orig_p` | `srcport` | int | Originating port |
| `id.resp_h` | `dstip` | IP | Responding host IP |
| `id.resp_p` | `dstport` | int | Responding port |
| `proto` | `protocol` | string | Transport protocol (tcp/udp/icmp) |
| `service` | `conn_service` | string | Application layer protocol detected |
| `duration` | `conn_duration` | float | Connection duration in seconds |
| `orig_bytes` | `conn_orig_bytes` | int | Bytes sent by originator |
| `resp_bytes` | `conn_resp_bytes` | int | Bytes sent by responder |
| `conn_state` | `conn_state` | string | Connection state (see table below) |
| `local_orig` | `conn_local_orig` | bool | Originator is local |
| `local_resp` | `conn_local_resp` | bool | Responder is local |
| `missed_bytes` | `conn_missed_bytes` | int | Bytes missed (packet loss) |
| `orig_pkts` | `conn_orig_pkts` | int | Packets sent by originator |
| `resp_pkts` | `conn_resp_pkts` | int | Packets sent by responder |

### conn_state Values

| State | Meaning | Detection Relevance |
|---|---|---|
| `SF` | Normal established and closed | Benign |
| `S0` | SYN sent, no response | Possible scan (no RST) |
| `REJ` | SYN sent, RST received | Port scan indicator (rules 100903, 100904) |
| `RSTO` | Originator reset | Aborted connection |
| `RSTR` | Responder reset | Service refused |
| `OTH` | No SYN, mid-stream | Partial capture |

## dns.log — DNS Queries

| Zeek Field | Wazuh Decoder Field | Type | Description |
|---|---|---|---|
| `id.orig_h` | `srcip` | IP | Client IP |
| `id.orig_p` | `srcport` | int | Client port |
| `id.resp_h` | `dstip` | IP | DNS server IP |
| `id.resp_p` | `dstport` | int | DNS server port (usually 53) |
| `proto` | `protocol` | string | udp or tcp |
| `trans_id` | `dns_transaction_id` | int | DNS transaction ID |
| `query` | `dns_query` | string | Queried domain name |
| `qtype_name` | `dns_qtype` | string | Query type (A, AAAA, MX, etc.) |
| `rcode_name` | `dns_rcode` | string | Response code (NOERROR, NXDOMAIN, etc.) |
| `AA` | `dns_authoritative` | bool | Authoritative answer |
| `TC` | `dns_truncated` | bool | Truncated response |
| `RD` | `dns_recursion_desired` | bool | Recursion desired |
| `RA` | `dns_recursion_available` | bool | Recursion available |
| `rejected` | `dns_rejected` | bool | Query rejected by server |

### dns_rcode Values

| Code | Meaning | Detection Relevance |
|---|---|---|
| `NOERROR` | Successful | Normal |
| `NXDOMAIN` | Domain does not exist | Possible DGA or typo |
| `SERVFAIL` | Server failure | DNS infrastructure issue |
| `REFUSED` | Query refused | Possible DNS filtering |

## ssl.log — TLS/SSL Connections

| Zeek Field | Wazuh Decoder Field | Type | Description |
|---|---|---|---|
| `id.orig_h` | `srcip` | IP | Client IP |
| `id.resp_h` | `dstip` | IP | Server IP |
| `id.resp_p` | `dstport` | int | Server port (usually 443) |
| `version` | `ssl_version` | string | TLS version (TLSv12, TLSv13) |
| `cipher` | `ssl_cipher` | string | Cipher suite negotiated |
| `curve` | `ssl_curve` | string | Elliptic curve (if applicable) |
| `server_name` | `ssl_server_name` | string | SNI hostname |
| `resumed` | `ssl_resumed` | bool | Session resumed |
| `established` | `ssl_established` | bool | Handshake completed |
| `validation_status` | `ssl_validation_status` | string | Certificate validation result |
| `next_protocol` | `ssl_next_protocol` | string | ALPN protocol (h2, http/1.1) |

### ssl_validation_status Values

| Value | Meaning | Rule |
|---|---|---|
| `ok` | Certificate valid | No alert |
| `self signed certificate` | Self-signed cert | Rule 100906 (level 8) |
| `certificate has expired` | Expired cert | Rule 100907 (level 12) |
| `unable to get local issuer certificate` | Unknown CA | Investigate |
| `hostname mismatch` | Cert CN/SAN mismatch | Investigate |

## notice.log — Zeek Notices

Zeek's built-in detection framework. Fields vary by notice type.
Key field: `note` — the notice type identifier.

## software.log — Software Detection

| Zeek Field | Wazuh Decoder Field | Type | Description |
|---|---|---|---|
| `host` | `srcip` | IP | Host running the software |
| `software_type` | `software_type` | string | Category (HTTP::BROWSER, etc.) |
| `name` | `software_name` | string | Software name |
| `unparsed_version` | `software_version` | string | Raw version string |
