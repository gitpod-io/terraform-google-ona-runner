#!/bin/sh
set -eu

# Certbot entrypoint for Cloud Run Job.
# Obtains/renews a wildcard certificate via DNS-01 challenge against Cloud DNS,
# then writes the certificate to Secret Manager using the metadata service token.
#
# Required environment variables:
#   RUNNER_DOMAIN      - Domain to obtain certificate for
#   DNS_PROJECT_ID     - GCP project containing the Cloud DNS zone
#   ACME_EMAIL         - Email for Let's Encrypt registration
#   PROJECT_ID         - GCP project for Secret Manager
#   CERT_SECRET_NAME   - Secret Manager secret name to write the certificate to
#
# The GCS bucket is mounted at /mnt/certbot-state via Cloud Run GCS FUSE volume mount.

CERTBOT_CONFIG_DIR="/mnt/certbot-state/letsencrypt"
CERTBOT_WORK_DIR="/tmp/certbot-work"
CERTBOT_LOGS_DIR="/tmp/certbot-logs"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "Starting certbot certificate management"
log "Domain: ${RUNNER_DOMAIN}"
log "DNS Project: ${DNS_PROJECT_ID}"
log "ACME Email: ${ACME_EMAIL}"

# Ensure directories exist
mkdir -p "${CERTBOT_CONFIG_DIR}" "${CERTBOT_WORK_DIR}" "${CERTBOT_LOGS_DIR}"

# Run certbot
log "Running certbot..."
certbot certonly \
  --dns-google \
  --dns-google-project "${DNS_PROJECT_ID}" \
  --dns-google-propagation-seconds 120 \
  -d "${RUNNER_DOMAIN}" \
  -d "*.${RUNNER_DOMAIN}" \
  --non-interactive \
  --agree-tos \
  --email "${ACME_EMAIL}" \
  --keep-until-expiring \
  --config-dir "${CERTBOT_CONFIG_DIR}" \
  --work-dir "${CERTBOT_WORK_DIR}" \
  --logs-dir "${CERTBOT_LOGS_DIR}"

CERTBOT_EXIT=$?

if [ $CERTBOT_EXIT -ne 0 ]; then
  log "ERROR: certbot exited with code ${CERTBOT_EXIT}"
  if [ -d "${CERTBOT_LOGS_DIR}" ]; then
    log "Certbot logs:"
    cat "${CERTBOT_LOGS_DIR}"/letsencrypt.log 2>/dev/null || true
  fi
  exit 1
fi

log "Certbot completed successfully"

# Check if certificate files exist
CERT_PATH="${CERTBOT_CONFIG_DIR}/live/${RUNNER_DOMAIN}/fullchain.pem"
KEY_PATH="${CERTBOT_CONFIG_DIR}/live/${RUNNER_DOMAIN}/privkey.pem"

if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
  log "No certificate files found — certbot may not have needed to issue/renew"
  exit 0
fi

log "Certificate obtained. Writing to Secret Manager..."

# Export for python script
export CERT_PATH KEY_PATH

# Use python3 (available in certbot image) for all API interactions.
# This avoids dependency on curl/wget/jq which may not be in the image.
python3 << 'PYTHON_SCRIPT'
import json
import os
import sys
import base64
import urllib.request
import urllib.error
from datetime import datetime

def log(msg):
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}")

cert_path = os.environ["CERT_PATH"]
key_path = os.environ["KEY_PATH"]
project_id = os.environ["PROJECT_ID"]
secret_name = os.environ["CERT_SECRET_NAME"]

# Get access token from metadata service
try:
    req = urllib.request.Request(
        "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
        headers={"Metadata-Flavor": "Google"}
    )
    resp = urllib.request.urlopen(req, timeout=10)
    token_data = json.loads(resp.read())
    access_token = token_data["access_token"]
except Exception as e:
    log(f"ERROR: Failed to get access token: {e}")
    sys.exit(1)

# Read cert and key
with open(cert_path) as f:
    cert_content = f.read()
with open(key_path) as f:
    key_content = f.read()

# Format as JSON matching the existing GSM secret format
secret_json = json.dumps({"certificate": cert_content, "privateKey": key_content})

# Base64-encode for the API
encoded_data = base64.b64encode(secret_json.encode()).decode()

# Write new version to Secret Manager
url = f"https://secretmanager.googleapis.com/v1/projects/{project_id}/secrets/{secret_name}:addVersion"
payload = json.dumps({"payload": {"data": encoded_data}}).encode()

try:
    req = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    resp = urllib.request.urlopen(req, timeout=30)
    result = json.loads(resp.read())
    log(f"Certificate written to Secret Manager: {result.get('name', secret_name)}")
except urllib.error.HTTPError as e:
    body = e.read().decode()
    log(f"ERROR: Failed to write to Secret Manager: {e.code} {body}")
    sys.exit(1)
except Exception as e:
    log(f"ERROR: Failed to write to Secret Manager: {e}")
    sys.exit(1)

log("Done")
PYTHON_SCRIPT

# Log certificate expiry for visibility
openssl x509 -in "$CERT_PATH" -noout -enddate 2>/dev/null || true
