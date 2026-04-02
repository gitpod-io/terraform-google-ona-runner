#!/bin/bash
# GCP Runner End-to-End Test
# 
# This script tests the complete lifecycle of a GCP runner deployment:
# 1. Creates a runner via Ona API (using organization-specific PAT)
# 2. Deploys infrastructure using Terraform
# 3. Waits for runner to come online
# 4. Cleans up all resources
#
# Required: GCP_PROJECT_ID, GITPOD_TOKEN (org-specific PAT)
# Optional: GCP_REGION (defaults to us-central1)
#           GITPOD_API_ENDPOINT (defaults to https://app.gitpod.io/api)
#           GOOGLE_APPLICATION_CREDENTIALS (path to service account key)
#
# Usage: ./scripts/e2e-test.sh [--help]

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/examples/runner-with-networking"

# Exit codes
readonly EXIT_GENERAL_FAILURE=1
readonly EXIT_CONFIG_ERROR=2
readonly EXIT_AUTH_FAILURE=3
readonly EXIT_INFRA_FAILURE=4
readonly EXIT_CLEANUP_FAILURE=5

# Global variables for cleanup tracking
RUNNER_ID=""
TERRAFORM_APPLIED=false
TEST_ID=""
TFVARS_FILE=""

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

log_info() {
    log "INFO: $*"
}

log_error() {
    log "ERROR: $*"
}

log_warn() {
    log "WARN: $*"
}

# Cleanup function - always runs on exit
cleanup() {
    local original_exit_code=$?
    local cleanup_exit_code=0
    log_info "Starting cleanup process..."
    log_info "Original exit code: $original_exit_code"
    
    # Destroy Terraform infrastructure first (while runner is still available)
    if [[ "$TERRAFORM_APPLIED" == "true" ]]; then
        log_info "Destroying Terraform infrastructure..."
        log_info "This includes any partially created resources from failed/timed-out apply"
        if ! destroy_terraform; then
            log_error "Failed to destroy Terraform infrastructure"
            cleanup_exit_code=$EXIT_CLEANUP_FAILURE
        fi
    else
        log_info "Skipping Terraform destroy - no apply was attempted"
    fi
    
    # Clean up generated files
    if [[ -n "$TFVARS_FILE" && -f "$TFVARS_FILE" ]]; then
        log_info "Cleaning up tfvars file: $TFVARS_FILE"
        rm -f "$TFVARS_FILE"
    fi
    
    # Clean up delegation terraform file
    local delegation_tf="$TERRAFORM_DIR/e2e-delegation.tf"
    if [[ -f "$delegation_tf" ]]; then
        log_info "Cleaning up delegation file: $delegation_tf"
        rm -f "$delegation_tf"
    fi
    

    
    # Delete runner last (after infrastructure is cleaned up)
    if [[ -n "$RUNNER_ID" ]]; then
        log_info "Deleting runner: $RUNNER_ID"
        if ! delete_runner "$RUNNER_ID"; then
            log_error "Failed to delete runner"
            cleanup_exit_code=$EXIT_CLEANUP_FAILURE
        fi
    fi
    
    log_info "Cleanup completed"
    
    # Show final result message based on original exit code
    if [[ $original_exit_code -eq 0 ]]; then
        echo ""
        echo "=========================================="
        echo "🎉 E2E TEST COMPLETED SUCCESSFULLY!"
        echo "=========================================="
        echo "Test ID: $TEST_ID"
        echo "All resources have been cleaned up."
        echo ""
    else
        echo ""
        echo "=========================================="
        echo "❌ E2E TEST FAILED!"
        echo "=========================================="
        echo "Test ID: $TEST_ID"
        echo "Exit code: $original_exit_code"
        echo "Check the logs above for error details."
        echo ""
        case $original_exit_code in
            "$EXIT_CONFIG_ERROR")
                echo "Issue: Configuration or environment error"
                echo "Fix: Check required environment variables and tool installations"
                ;;
            "$EXIT_AUTH_FAILURE")
                echo "Issue: Authentication failure"
                echo "Fix: Verify GITPOD_TOKEN has runner management permissions and you are org admin"
                ;;
            "$EXIT_INFRA_FAILURE")
                echo "Issue: Infrastructure deployment failure"
                echo "Fix: Check GCP quotas, permissions, and Terraform configuration"
                ;;
            "$EXIT_CLEANUP_FAILURE")
                echo "Issue: Cleanup failure"
                echo "Fix: Manual cleanup may be required - check GCP console for orphaned resources"
                ;;
            *)
                echo "Issue: General failure"
                echo "Fix: Check the error logs above for specific details"
                ;;
        esac
        echo ""
    fi
    
    # Show additional cleanup failure message if needed
    if [[ $cleanup_exit_code -ne 0 ]]; then
        echo ""
        echo "⚠️  CLEANUP WARNING:"
        echo "Cleanup failed during resource removal."
        echo "Manual cleanup may be required - check GCP console for orphaned resources."
        echo ""
    fi
    
    exit $original_exit_code
}

# Set up cleanup trap
trap cleanup EXIT

# Environment validation
validate_environment() {
    log_info "Validating environment..."
    
    local required_vars=(
        "GCP_PROJECT_ID"
        "GITPOD_TOKEN"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_error "Please set all required variables before running the test"
        exit $EXIT_CONFIG_ERROR
    fi
    
    # Check required tools
    local required_tools=("curl" "jq" "terraform" "gcloud")
    local missing_tools=()
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit $EXIT_CONFIG_ERROR
    fi
    
    # Set default API endpoint if not provided
    GITPOD_API_ENDPOINT="${GITPOD_API_ENDPOINT:-https://app.gitpod.io/api}"
    export GITPOD_API_ENDPOINT
    log_info "Using Ona API endpoint: $GITPOD_API_ENDPOINT"
    
    # Set default GCP region if not provided
    GCP_REGION="${GCP_REGION:-us-central1}"
    export GCP_REGION
    log_info "Using GCP region: $GCP_REGION"
    
    # Validate GCP authentication
    validate_gcp_authentication
    
    # Generate test ID
    TEST_ID="${E2E_TEST_ID:-e2e-$(date +%s)}"
    log_info "Test ID: $TEST_ID"
    
    log_info "Environment validation completed"
}

# GCP authentication validation
validate_gcp_authentication() {
    log_info "Validating GCP authentication..."
    
    # Check if service account key file is provided
    if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
        if [[ ! -f "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
            log_error "Service account key file not found: $GOOGLE_APPLICATION_CREDENTIALS"
            exit $EXIT_CONFIG_ERROR
        fi
        
        log_info "Using service account key file: $GOOGLE_APPLICATION_CREDENTIALS"
        
        # Activate service account
        if ! gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS" --quiet; then
            log_error "Failed to activate service account"
            exit $EXIT_AUTH_FAILURE
        fi
        
        log_info "Service account activated successfully"
    else
        log_info "No GOOGLE_APPLICATION_CREDENTIALS provided, using existing gcloud authentication"
    fi
    
    # Set the GCP project
    if ! gcloud config set project "$GCP_PROJECT_ID" --quiet; then
        log_error "Failed to set GCP project: $GCP_PROJECT_ID"
        exit $EXIT_CONFIG_ERROR
    fi
    
    # Verify authentication by testing access to the project
    if ! gcloud projects describe "$GCP_PROJECT_ID" --quiet >/dev/null 2>&1; then
        log_error "Cannot access GCP project: $GCP_PROJECT_ID"
        log_error "Please check:"
        log_error "  1. Project exists and you have access"
        log_error "  2. Service account has necessary permissions"
        log_error "  3. Authentication is properly configured"
        exit $EXIT_AUTH_FAILURE
    fi
    
    log_info "GCP authentication validated for project: $GCP_PROJECT_ID"
}

# Ona API functions
gitpod_api_call() {
    local service="$1"
    local method="$2"
    local data="$3"
    
    local url="$GITPOD_API_ENDPOINT/gitpod.v1.$service/$method"
    
    curl -X POST \
        -H "Authorization: Bearer $GITPOD_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$data" \
        --silent \
        --show-error \
        --fail \
        "$url"
}

# Wrapper for RunnerService calls
runner_api_call() {
    local method="$1"
    local data="$2"
    gitpod_api_call "RunnerService" "$method" "$data"
}

create_runner() {
    log_info "Creating runner..."
    
    local request_data
    request_data=$(jq -n \
        --arg name "$TEST_ID" \
        --arg region "$GCP_REGION" \
        '{
            name: $name,
            provider: "RUNNER_PROVIDER_GCP",
            spec: {
                desiredPhase: "RUNNER_PHASE_ACTIVE",
                configuration: {
                    region: $region,
                    autoUpdate: true,
                    releaseChannel: "RUNNER_RELEASE_CHANNEL_STABLE"
                },
                variant: "RUNNER_VARIANT_ENTERPRISE"
            }
        }')
    
    local response
    if ! response=$(runner_api_call "CreateRunner" "$request_data"); then
        log_error "Failed to create runner. Check that:"
        log_error "  1. GITPOD_TOKEN has runner management permissions"
        log_error "  2. You are an organization admin"
        log_error "  3. GCP runner creation is enabled for your organization"
        exit $EXIT_AUTH_FAILURE
    fi
    
    RUNNER_ID=$(echo "$response" | jq -r '.runner.runnerId')
    local access_token
    # Try exchangeToken first (new API), fallback to accessToken (deprecated)
    access_token=$(echo "$response" | jq -r '.exchangeToken // .accessToken')
    
    if [[ "$RUNNER_ID" == "null" || -z "$RUNNER_ID" ]]; then
        log_error "Failed to extract runner ID from response"
        exit $EXIT_GENERAL_FAILURE
    fi
    
    if [[ "$access_token" == "null" || -z "$access_token" ]]; then
        log_error "Failed to extract access token from response"
        exit $EXIT_GENERAL_FAILURE
    fi
    
    log_info "Created runner: $RUNNER_ID"
    
    # Export for terraform
    export TF_VAR_runner_id="$RUNNER_ID"
    export TF_VAR_runner_token="$access_token"
}

get_runner_status() {
    local runner_id="$1"
    
    local request_data
    request_data=$(jq -n --arg id "$runner_id" '{runnerId: $id}')
    
    local response
    if ! response=$(runner_api_call "GetRunner" "$request_data"); then
        return 1
    fi
    
    echo "$response" | jq -r '.runner.status.phase // "UNKNOWN"'
}

delete_runner() {
    local runner_id="$1"
    
    log_info "Deleting runner: $runner_id"
    
    local request_data
    request_data=$(jq -n --arg id "$runner_id" '{runnerId: $id}')
    
    if runner_api_call "DeleteRunner" "$request_data" >/dev/null; then
        log_info "Successfully deleted runner"
        return 0
    else
        log_warn "Failed to delete runner (may not exist)"
        return 1
    fi
}

# Terraform functions
setup_terraform() {
    log_info "Setting up Terraform configuration..."
    
    # Create tfvars file for this test
    TFVARS_FILE="$TERRAFORM_DIR/e2e-test-$TEST_ID.tfvars"
    
    cat > "$TFVARS_FILE" <<EOF
# E2E Test Configuration - Generated by e2e-test.sh
project_id = "$GCP_PROJECT_ID"
region = "$GCP_REGION"
zones = ["$GCP_REGION-a", "$GCP_REGION-b", "$GCP_REGION-c"]
runner_name = "$TEST_ID"
runner_id = "$TF_VAR_runner_id"
runner_token = "$TF_VAR_runner_token"
runner_domain = "$TEST_ID.tests.doptig.com"

# E2E-specific settings
labels = {
  "environment" = "e2e-test"
  "managed-by"  = "terraform"
  "purpose"     = "testing"
  "test-id"     = "$TEST_ID"
}
EOF
    
    log_info "Created tfvars file: $TFVARS_FILE"
    
    # Create additional Terraform configuration for DNS delegation
    # Only create delegation if we can access the parent DNS project and zone
    local delegation_tf="$TERRAFORM_DIR/e2e-delegation.tf"
    
    # Check if we have access to the DNS project and the parent zone
    if gcloud dns managed-zones describe "tests-doptig-com" --project="dns-for-playgrounds" --quiet >/dev/null 2>&1; then
        log_info "Creating DNS delegation configuration..."
        cat > "$delegation_tf" <<EOF
# E2E Test DNS Delegation - Generated by e2e-test.sh
# This creates delegation from tests.doptig.com to the test subdomain

# Create NS delegation record in the parent tests.doptig.com zone
# Uses the DNS zone created by the main module
resource "google_dns_record_set" "delegation" {
  name         = "\${var.runner_domain}."
  type         = "NS"
  ttl          = 300
  managed_zone = "tests-doptig-com"
  project      = "dns-for-playgrounds"
  
  # Reference the name servers from the DNS module output
  rrdatas = module.dns.ns_records
  
  depends_on = [module.dns]
}
EOF
        log_info "Created delegation configuration: $delegation_tf"
    else
        log_warn "Cannot access tests-doptig-com zone in dns-for-playgrounds project"
        log_warn "Skipping DNS delegation - test will still work but DNS resolution may not"
        log_warn "To enable DNS delegation, ensure you have access to dns-for-playgrounds project"
        log_warn "and the tests-doptig-com managed zone exists"
        
        # Create empty delegation file
        cat > "$delegation_tf" <<EOF
# E2E Test DNS Delegation - Skipped due to access issues
# DNS delegation was skipped because access to dns-for-playgrounds/tests-doptig-com was not available
# The test will still work, but external DNS resolution may not function
EOF
        log_info "Created empty delegation configuration: $delegation_tf"
    fi
    
    # Initialize terraform
    cd "$TERRAFORM_DIR"
    log_info "Initializing Terraform..."
    if ! terraform init -input=false -no-color; then
        log_error "Terraform init failed"
        exit $EXIT_INFRA_FAILURE
    fi
    
    log_info "Terraform setup completed"
}

apply_terraform() {
    log_info "Applying Terraform configuration..."
    log_info "This may take 10-20 minutes for full infrastructure deployment..."
    
    cd "$TERRAFORM_DIR"
    
    # Set flag before starting apply to ensure cleanup runs even on timeout/failure
    TERRAFORM_APPLIED=true
    
    if terraform apply -auto-approve -input=false -no-color -var-file="$(basename "$TFVARS_FILE")"; then
        log_info "Terraform apply completed successfully"
        
        # Extract and display key information
        local lb_ip
        lb_ip=$(terraform output -raw load_balancer_ip 2>/dev/null || echo "N/A")
        local dns_zone
        dns_zone=$(terraform output -raw dns_zone_name 2>/dev/null || echo "N/A")
        
        log_info "Infrastructure deployed successfully!"
        log_info "  • Load Balancer IP: $lb_ip"
        log_info "  • DNS Zone: $dns_zone"
        log_info "  • Runner Domain: $TEST_ID.tests.doptig.com"
    else
        log_error "Terraform apply failed"
        exit $EXIT_INFRA_FAILURE
    fi
}

destroy_terraform() {
    log_info "Destroying Terraform infrastructure..."
    
    cd "$TERRAFORM_DIR"
    
    if [[ -f "$(basename "$TFVARS_FILE")" ]]; then
        if terraform destroy -auto-approve -input=false -no-color -var-file="$(basename "$TFVARS_FILE")"; then
            TERRAFORM_APPLIED=false
            log_info "Terraform destroy completed successfully"
            return 0
        else
            log_error "Terraform destroy failed"
            return 1
        fi
    else
        log_warn "Tfvars file not found, attempting destroy without var-file"
        if terraform destroy -auto-approve -input=false -no-color; then
            TERRAFORM_APPLIED=false
            log_info "Terraform destroy completed successfully"
            return 0
        else
            log_error "Terraform destroy failed"
            return 1
        fi
    fi
}

# Wait for runner to come online
wait_for_runner_online() {
    log_info "Waiting for runner to come online..."
    
    local max_attempts=90  # 30 minutes with 20s intervals
    local attempt=1
    local sleep_time=20
    
    while [[ $attempt -le $max_attempts ]]; do
        log_info "Checking runner status (attempt $attempt/$max_attempts)..."
        
        local status
        if status=$(get_runner_status "$RUNNER_ID"); then
            log_info "Runner status: $status"
            
            if [[ "$status" == "RUNNER_PHASE_ACTIVE" ]]; then
                log_info "✅ Runner is online and ready for use!"
                return 0
            fi
        else
            log_warn "Failed to get runner status"
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log_info "Waiting ${sleep_time}s before next check..."
            sleep $sleep_time
        fi
        
        ((attempt++))
    done
    
    log_error "Runner failed to come online within 30 minutes timeout"
    exit $EXIT_GENERAL_FAILURE
}

# Main test workflow
run_e2e_test() {
    log_info "Starting GCP Runner E2E test..."
    
    validate_environment
    create_runner
    setup_terraform
    apply_terraform
    wait_for_runner_online
    
    log_info "All test phases completed successfully!"
}

# Main function
main() {
    case "${1:-}" in
        --help|-h)
            echo "Usage: $0 [--help]"
            echo ""
            echo "Options:"
            echo "  --help, -h      Show this help message"
            echo ""
            echo "Environment variables required:"
            echo "  GCP_PROJECT_ID      GCP project ID for testing"
            echo "  GITPOD_TOKEN        Organization-specific PAT token with runner management permissions"
            echo ""
            echo "Optional:"
            echo "  GCP_REGION          GCP region (default: us-central1)"
            echo "  GITPOD_API_ENDPOINT API endpoint (default: https://app.gitpod.io/api)"
            echo "  E2E_TEST_ID         Custom test identifier"
            echo ""
            echo "GCP Authentication (choose one):"
            echo "  GOOGLE_APPLICATION_CREDENTIALS  Path to service account key file"
            echo "  OR use existing gcloud authentication (gcloud auth login)"
            echo ""
            echo "Note: Cleanup is handled automatically via EXIT trap"
            ;;
        "")
            run_e2e_test
            ;;
        *)
            log_error "Unknown option: '$1'"
            echo "Use --help for usage information"
            echo "Valid usage: $0 [--help]"
            exit $EXIT_CONFIG_ERROR
            ;;
    esac
}

# Run main function with all arguments
main "$@"
