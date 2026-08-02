#!/usr/bin/env bash
set -euo pipefail
source .env
mkdir -p certs

openssl req -x509 -newkey rsa:4096 \
  -keyout certs/device.key \
  -out certs/device.crt \
  -days 825 -nodes \
  -subj "/CN=PakkuConnect/O=Pakku/C=US"

openssl pkcs12 -export \
  -in certs/device.crt \
  -inkey certs/device.key \
  -out certs/device.p12 \
  -passout pass:"$P12_PASSWORD"

# DER form — this is what Android's X509Certificate.getEncoded() returns,
# so the pinned fingerprint (ADR-004) must be computed from THIS file,
# not the PEM above.
openssl x509 -in certs/device.crt -outform DER -out certs/device.der

FP=$(openssl dgst -sha256 certs/device.der | awk '{print $2}')
echo "Certificate SHA-256 fingerprint (DER): $FP"
echo "Certificates ready in certs/"
