#!/usr/bin/env bash
# generate-certs.sh — Generate self-signed TLS certificates for development.
#
# WARNING: These certificates are for local development only.
# Do not use in production. Replace with proper PKI before any
# internet-facing deployment.
#
# Outputs to: docker/certs/
# Required by: docker/docker-compose.yml

set -euo pipefail

CERTS_DIR="$(dirname "$0")/../docker/certs"
mkdir -p "$CERTS_DIR"

echo "→ Generating root CA..."
openssl genrsa -out "$CERTS_DIR/root-ca-key.pem" 4096
openssl req -new -x509 -sha256 -key "$CERTS_DIR/root-ca-key.pem" \
  -subj "/C=US/O=network-security-lab/CN=Root CA" \
  -out "$CERTS_DIR/root-ca.pem" -days 3650

# Copy root CA for manager (same CA, different filename expected by Wazuh)
cp "$CERTS_DIR/root-ca.pem" "$CERTS_DIR/root-ca-manager.pem"

generate_cert() {
  local name="$1"
  local cn="$2"
  echo "→ Generating cert for $name..."
  openssl genrsa -out "$CERTS_DIR/${name}-key.pem" 2048
  openssl req -new -key "$CERTS_DIR/${name}-key.pem" \
    -subj "/C=US/O=network-security-lab/CN=${cn}" \
    -out "$CERTS_DIR/${name}.csr"
  openssl x509 -req -in "$CERTS_DIR/${name}.csr" \
    -CA "$CERTS_DIR/root-ca.pem" \
    -CAkey "$CERTS_DIR/root-ca-key.pem" \
    -CAcreateserial \
    -out "$CERTS_DIR/${name}.pem" \
    -days 3650 -sha256
  rm "$CERTS_DIR/${name}.csr"
}

generate_cert "wazuh-indexer"  "wazuh-indexer"
generate_cert "wazuh-manager"  "wazuh-manager"
generate_cert "wazuh-dashboard" "wazuh-dashboard"
generate_cert "admin"          "admin"
generate_cert "filebeat"       "filebeat"

# Set restrictive permissions on private keys
chmod 600 "$CERTS_DIR"/*-key.pem

echo ""
echo "✓ Certificates written to $CERTS_DIR"
echo "  Root CA:   root-ca.pem"
echo "  Indexer:   wazuh-indexer.pem / wazuh-indexer-key.pem"
echo "  Manager:   wazuh-manager.pem / wazuh-manager-key.pem"
echo "  Dashboard: wazuh-dashboard.pem / wazuh-dashboard-key.pem"
echo "  Admin:     admin.pem / admin-key.pem"
echo ""
echo "⚠  For development only. Replace with proper PKI in production."
