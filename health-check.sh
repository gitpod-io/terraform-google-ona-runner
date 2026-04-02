#!/bin/bash
set -euo pipefail

# Function to print final error message
print_final_error() {
  echo ""
  echo "❌ HEALTH VALIDATION FAILED"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "The health validation failed, causing terraform apply to fail."
  echo "This is expected behavior when instances are not healthy."
  echo ""
  echo "Next steps:"
  echo "1. Check the error details above for specific failure reasons"
  echo "2. Review GCP Console for instance and load balancer status"
  echo "3. Check instance startup logs if instances are not running"
  echo "4. Verify health check configuration if instances are not healthy"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Set trap to print final error message on any exit
trap 'print_final_error' EXIT

# Configuration
TIMEOUT=${HEALTH_CHECK_TIMEOUT:-600}  # Default 10 minutes, configurable via env var
SLEEP=10

# Check if required environment variables are set
if [[ -z "${RUNNER_IGM:-}" || -z "${GOOGLE_OAUTH_TOKEN:-}" || -z "${PROJECT_ID:-}" ]]; then
  echo "❌ Error: Required environment variables not set"
  echo "   Missing: RUNNER_IGM, GOOGLE_OAUTH_TOKEN, or PROJECT_ID"
  exit 1
fi

# Get token from environment variable
TOKEN="$GOOGLE_OAUTH_TOKEN"

# Helper functions
auth_hdr() {
  printf 'Authorization: Bearer %s' "$TOKEN"
}

api_call() {
  local method="$1"
  local url="$2"
  local data="${3:-}"
  
  # Remove trailing slash
  url="${url%/}"
  
  local curl_output
  local curl_exit_code
  
  if [[ "$method" == "POST" && -n "$data" ]]; then
    curl_output=$(curl -sSf -X POST -H "$(auth_hdr)" -H "Content-Type: application/json" -d "$data" "$url" 2>&1)
    curl_exit_code=$?
  elif [[ "$method" == "POST" ]]; then
    curl_output=$(curl -sSf -X POST -H "$(auth_hdr)" "$url" 2>&1)
    curl_exit_code=$?
  else
    curl_output=$(curl -sSf -H "$(auth_hdr)" "$url" 2>&1)
    curl_exit_code=$?
  fi
  
  if [[ $curl_exit_code -ne 0 ]]; then
    echo "❌ API call failed: $method $url" >&2
    echo "   Error: $curl_output" >&2
    return $curl_exit_code
  fi
  
  echo "$curl_output"
}

count_occurrences() {
  (grep -o "$2" <<<"$1" || true) | wc -l | tr -d '[:space:]'
}

# Test authentication first
echo "🔐 Testing GCP API authentication..."
if ! api_call GET "https://compute.googleapis.com/compute/v1/projects/$PROJECT_ID" >/dev/null; then
  echo "❌ Failed to authenticate with GCP API"
  echo "   Check that the OAuth token is valid and has required permissions"
  exit 1
fi
echo "✅ Authentication successful"

# Initial delay to allow MIG provisioning to start
INITIAL_DELAY=${HEALTH_CHECK_INITIAL_DELAY:-60}
if [[ "$INITIAL_DELAY" -gt 0 ]]; then
  echo "⏳ Waiting ${INITIAL_DELAY}s for initial MIG provisioning..."
  sleep "$INITIAL_DELAY"
fi

# Main validation loop
start_ts=$(date +%s)
end_ts=$((start_ts + TIMEOUT))

echo "🩺 Validating MIG health (timeout: ${TIMEOUT}s)..."
echo "📋 Configuration:"
echo "  - Runner MIG: $RUNNER_IGM"
echo "  - Runner target: $RUNNER_TARGET instances"
echo "  - Proxy MIG: $PROXY_IGM"
echo "  - Proxy target: $PROXY_TARGET instances"
echo ""

while : ; do
  now=$(date +%s)
  if (( now >= end_ts )); then
    echo ""
    echo "⏰ TIMEOUT: Health validation failed after ${TIMEOUT}s"
    echo ""
    echo "Final status:"
    echo "  - Runner MIG stable: $runner_stable"
    echo "  - Runner instances: $runner_running/$RUNNER_TARGET RUNNING, $runner_healthy/$RUNNER_TARGET HEALTHY"
    echo "  - Proxy MIG stable: $proxy_stable"
    if [[ "$proxy_all_ok" == "1" ]]; then
      echo "  - Proxy backends: healthy"
    else
      echo "  - Proxy backends: unhealthy"
    fi
    echo ""
    echo "Possible causes:"
    if [[ "$runner_stable" != "1" ]]; then
      echo "  • Runner MIG is not stable - instances may still be starting/updating"
    fi
    if [[ "$proxy_stable" != "1" ]]; then
      echo "  • Proxy MIG is not stable - instances may still be starting/updating"
    fi
    if (( runner_running < RUNNER_TARGET )); then
      echo "  • Not enough runner instances are RUNNING - check instance startup logs"
    fi
    if (( runner_healthy < RUNNER_TARGET )); then
      echo "  • Not enough runner instances are HEALTHY - check health check configuration"
    fi
    if (( proxy_all_ok != 1 )); then
      echo "  • Proxy backends are not healthy - check load balancer configuration"
    fi
    exit 1
  fi

  # Check MIG stability
  if ! runner_igm_json="$(api_call GET "$RUNNER_IGM")"; then
    echo ""
    echo "🚨 CRITICAL ERROR: Failed to get runner MIG status"
    echo "This indicates a problem with GCP API access or MIG configuration."
    echo "The MIG might not exist yet or there's a permission issue."
    exit 1
  fi
  
  if ! proxy_igm_json="$(api_call GET "$PROXY_IGM")"; then
    echo ""
    echo "🚨 CRITICAL ERROR: Failed to get proxy MIG status"
    echo "This indicates a problem with GCP API access or MIG configuration."
    echo "The MIG might not exist yet or there's a permission issue."
    exit 1
  fi

  runner_stable=$(echo "$runner_igm_json" | grep -c '"isStable": true' 2>/dev/null || echo "0")
  proxy_stable=$(echo "$proxy_igm_json" | grep -c '"isStable": true' 2>/dev/null || echo "0")
  
  # Debug: Show current MIG status
  runner_current_size=$(echo "$runner_igm_json" | grep -o '"currentActions":[^}]*"creating":[0-9]*' | grep -o '[0-9]*$' || echo "0")
  proxy_current_size=$(echo "$proxy_igm_json" | grep -o '"currentActions":[^}]*"creating":[0-9]*' | grep -o '[0-9]*$' || echo "0")
  
  if [[ "$runner_current_size" != "0" || "$proxy_current_size" != "0" ]]; then
    echo "🔄 MIG operations in progress:"
    [[ "$runner_current_size" != "0" ]] && echo "  - Runner: $runner_current_size instances being created"
    [[ "$proxy_current_size" != "0" ]] && echo "  - Proxy: $proxy_current_size instances being created"
  fi

  # Check runner instances (RUNNING + HEALTHY)
  if ! runner_list_json="$(api_call POST "$RUNNER_IGM/listManagedInstances")"; then
    echo ""
    echo "🚨 CRITICAL ERROR: Failed to list runner instances"
    echo "This indicates a problem with GCP API access or MIG configuration."
    exit 1
  fi

  runner_running=$(count_occurrences "$runner_list_json" '"instanceStatus": "RUNNING"')
  runner_healthy=$(count_occurrences "$runner_list_json" '"HEALTHY"')

  # Check proxy backend health (optional - skip if API calls fail)
  proxy_all_ok=1
  
  # Try to check SSL backend health
  ssl_health_data="{\"resourceGroupReference\": {\"group\": \"$PROXY_GROUP\"}}"
  if out="$(api_call POST "$PROXY_BACKEND_SSL/getHealth" "$ssl_health_data" 2>/dev/null)"; then
    healthy_count=$(count_occurrences "$out" '"healthState": "HEALTHY"')
    if [[ "$healthy_count" -lt "$PROXY_TARGET" ]]; then
      proxy_all_ok=0
      echo "⚠️  SSL Backend not fully healthy ($healthy_count/$PROXY_TARGET)"
    fi
  else
    echo "ℹ️  SSL backend health check not available (this is normal for some configurations)"
  fi
  
  # Try to check HTTP backend health
  http_health_data="{\"resourceGroupReference\": {\"group\": \"$PROXY_GROUP\"}}"
  if out="$(api_call POST "$PROXY_BACKEND_HTTP/getHealth" "$http_health_data" 2>/dev/null)"; then
    healthy_count=$(count_occurrences "$out" '"healthState": "HEALTHY"')
    if [[ "$healthy_count" -lt "$PROXY_TARGET" ]]; then
      proxy_all_ok=0
      echo "⚠️  HTTP Backend not fully healthy ($healthy_count/$PROXY_TARGET)"
    fi
  else
    echo "ℹ️  HTTP backend health check not available (this is normal for some configurations)"
  fi

  ok_runner_size=$(( runner_running >= RUNNER_TARGET ? 1 : 0 ))
  ok_runner_health=$(( runner_healthy >= RUNNER_TARGET ? 1 : 0 ))

  # Core validation: MIGs are stable and instances are healthy
  if (( runner_stable == 1 && proxy_stable == 1 && ok_runner_size == 1 && ok_runner_health == 1 )); then
    echo "✅ All core health checks passed"
    echo "  - Runner: $runner_running/$RUNNER_TARGET RUNNING, $runner_healthy/$RUNNER_TARGET HEALTHY"
    echo "  - Proxy: MIG stable"
    if [[ "$proxy_all_ok" == "1" ]]; then
      echo "  - Backend services: healthy"
    else
      echo "  - Backend services: health check unavailable (this is normal)"
    fi
    trap - EXIT  # Remove the error trap for successful exit
    exit 0
  fi

  echo "⏳ Waiting: runner stable=$runner_stable run=$runner_running/$RUNNER_TARGET health=$runner_healthy/$RUNNER_TARGET; proxy stable=$proxy_stable"
  
  # Show more details on first few iterations
  if (( (now - start_ts) < 60 )); then
    if [[ "$runner_stable" != "1" ]]; then
      echo "   → Runner MIG is not stable yet"
    fi
    if [[ "$proxy_stable" != "1" ]]; then
      echo "   → Proxy MIG is not stable yet"
    fi
    if (( runner_running < RUNNER_TARGET )); then
      echo "   → Only $runner_running/$RUNNER_TARGET runner instances are RUNNING"
    fi
    if (( runner_healthy < RUNNER_TARGET )); then
      echo "   → Only $runner_healthy/$RUNNER_TARGET runner instances are HEALTHY"
    fi
    if (( proxy_all_ok != 1 )); then
      echo "   → Some proxy backends are not healthy"
    fi
  fi
  
  sleep "$SLEEP"
done
