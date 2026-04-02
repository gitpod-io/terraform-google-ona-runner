# GCP Runner End-to-End Tests

End-to-end tests for the GCP Runner Terraform module that validate the complete lifecycle:

1. Creates a runner via Ona API
2. Deploys infrastructure using Terraform  
3. Waits for runner to come online
4. Cleans up all resources

## Quick Start

### Prerequisites

- **Tools**: `gcloud`, `terraform`, `curl`, `jq`
- **GCP Project**: With billing enabled and required APIs
- **Ona Organization**: With admin access for runner management

## GCP Project Setup

### 1. Create and Configure GCP Project

```bash
# Create a new project (or use existing)
export PROJECT_ID="gcp-runner-e2e-tests"
gcloud projects create $PROJECT_ID --name="GCP Runner E2E Tests"

# Enable billing (required for compute resources)
gcloud billing projects link $PROJECT_ID --billing-account=YOUR_BILLING_ACCOUNT_ID

# Set as default project
gcloud config set project $PROJECT_ID

# Enable all required APIs for the Terraform deployment
# This enables all APIs that the runner infrastructure needs
gcloud services enable \
    cloudresourcemanager.googleapis.com \
    iam.googleapis.com \
    serviceusage.googleapis.com \
    compute.googleapis.com \
    dns.googleapis.com \
    certificatemanager.googleapis.com \
    secretmanager.googleapis.com \
    storage.googleapis.com \
    pubsub.googleapis.com \
    cloudfunctions.googleapis.com \
    monitoring.googleapis.com \
    logging.googleapis.com \
    redis.googleapis.com \
    run.googleapis.com \
    vpcaccess.googleapis.com \
    servicenetworking.googleapis.com \
    artifactregistry.googleapis.com \
    iamcredentials.googleapis.com \
    --project=$PROJECT_ID

# Wait a moment for API enablement to propagate
echo "Waiting for APIs to be fully enabled..."
sleep 30
```

### 2. Create Service Account

```bash
# Create service account
gcloud iam service-accounts create gcp-runner-e2e-tests \
    --display-name="GCP Runner E2E Tests" \
    --description="Service account for GCP Runner E2E tests"

# Get service account email
export SA_EMAIL="gcp-runner-e2e-tests@${PROJECT_ID}.iam.gserviceaccount.com"
```

### 3. Assign Required Roles

```bash
# Main project roles
roles=(
    "roles/compute.admin"
    "roles/dns.admin"
    "roles/iam.serviceAccountAdmin"
    "roles/iam.serviceAccountUser"
    "roles/iam.roleAdmin"
    "roles/resourcemanager.projectIamAdmin"
    "roles/certificatemanager.owner"
    "roles/secretmanager.admin"
    "roles/storage.admin"
    "roles/pubsub.admin"
    "roles/cloudfunctions.admin"
    "roles/serviceusage.serviceUsageAdmin"
    "roles/monitoring.admin"
    "roles/logging.admin"
    "roles/artifactregistry.admin"
    "roles/servicenetworking.networksAdmin"
    "roles/redis.admin"
)

for role in "${roles[@]}"; do
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:$SA_EMAIL" \
        --role="$role"
done
```

### 4. Create and Download Service Account Key

```bash
# Create key file
gcloud iam service-accounts keys create ~/gcp-runner-e2e-key.json \
    --iam-account=$SA_EMAIL

# Set environment variable
export GOOGLE_APPLICATION_CREDENTIALS="$HOME/gcp-runner-e2e-key.json"
```

### 5. DNS Project Setup

The E2E tests require access to the `dns-for-playgrounds` project to create DNS delegation records in the `tests-doptig-com` managed zone. This enables proper DNS resolution for the test runner domain (`$TEST_ID.tests.doptig.com`).

```bash
# Grant DNS admin permissions to the dns-for-playgrounds project
gcloud projects add-iam-policy-binding dns-for-playgrounds \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/dns.admin"

# Verify access to the required DNS zone
gcloud dns managed-zones describe "tests-doptig-com" --project="dns-for-playgrounds"
```

**Important**: Without this setup, the E2E script will skip DNS delegation and show warnings, and **the tests will fail**. The runner cannot come online without proper DNS resolution because it needs to communicate with Gitpod's control plane via `https://${runner_id}.${runner_domain}/`.

### Environment Setup

```bash
# Required
export GCP_PROJECT_ID="gcp-runner-e2e-tests"
export GITPOD_TOKEN="your-organization-pat-token"
export GOOGLE_APPLICATION_CREDENTIALS="$HOME/gcp-runner-e2e-key.json"

# Optional (with defaults)
export GCP_REGION="us-central1"                        # Default: us-central1
export GITPOD_API_ENDPOINT="https://app.gitpod.io/api" # Default
export E2E_TEST_ID="my-test-$(date +%s)"               # Auto-generated if not set
```

### Running Tests

```bash
# Run the test
./tests/e2e/scripts/e2e-test.sh

# Show help
./tests/e2e/scripts/e2e-test.sh --help
```

## GitHub Actions

Runs daily at 6 AM UTC and can be triggered manually.

### Required Secrets

- `E2E_GITPOD_TOKEN` - Organization-specific Ona PAT
- `E2E_GOOGLE_APPLICATION_CREDENTIALS` - Service account key JSON
- `NEXT_ALERTS_SLACK_WEBHOOK` - Slack webhook for failure notifications

### Optional Variables

- `E2E_GCP_PROJECT_ID` - GCP project ID (defaults to gcp-runner-e2e-tests)
- `E2E_GCP_REGION` - GCP region (defaults to us-central1)
- `E2E_GITPOD_API_ENDPOINT` - API endpoint (defaults to https://app.gitpod.io/api)

## Service Account Permissions

The service account needs these roles in the **main GCP project**:
- `Compute Admin` - For VMs, disks, networks, and load balancers
- `DNS Administrator` - For DNS zones and records
- `Service Account Admin` - For creating and managing service accounts
- `Service Account User` - For using service accounts in compute resources
- `Role Administrator` - For creating and managing custom IAM roles
- `Project IAM Admin` - For IAM role bindings and custom roles
- `Certificate Manager Owner` - For SSL certificate management (includes delete permissions)
- `Secret Manager Admin` - For storing sensitive configuration
- `Storage Admin` - For build cache buckets
- `Pub/Sub Admin` - For event-driven reconciliation
- `Cloud Functions Admin` - For auth proxy functions
- `Service Usage Admin` - For enabling required APIs
- `Monitoring Admin` - For health checks and alerting
- `Logging Admin` - For log management
- `Artifact Registry Admin` - For container image repositories
- `Service Networking Networks Admin` - For VPC peering and private service access

**DNS Project Permissions** (mandatory - tests will fail without this):
The service account also needs:
- `DNS Administrator` role in the **dns-for-playgrounds project** limited to the **tests-doptig-com zone** using IAM conditions
