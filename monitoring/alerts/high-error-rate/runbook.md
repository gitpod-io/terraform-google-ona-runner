# GCP Runner High Error Rate

## Alert Description
This alert fires when the GCP Runner experiences a high rate of environment operation failures. It monitors:
- `rate(gitpod_gcp_compute_environment_operations_total{status="error"}[5m]) > 0.1`
- Triggers when >10% of environment operations fail over 5 minutes

## Impact
**Critical Impact:** Users experiencing widespread failures
- Environment creation failures
- Environment start/stop operation failures
- Degraded user experience and productivity
- Potential SLA breach if sustained

## Prerequisites

Set up the required environment variables before running debugging commands:

```bash
# Set these variables based on your Terraform deployment
export PROJECT_ID="your-gcp-project-id"
export REGION="your-region"  # e.g., us-central1
export RUNNER_ID="your-runner-id"  # The runner ID from your Terraform configuration

# Verify the variables are set
echo "Project: $PROJECT_ID, Region: $REGION, Runner: $RUNNER_ID"
```

## Debugging Steps

### 1. Get Instance Information
```bash
# Get runner instance details
INSTANCE_NAME=$(gcloud compute instance-groups managed list-instances ${RUNNER_ID}-runner-mig \
  --region=${REGION} --project=${PROJECT_ID} --format="value(instance)" | head -1)

ZONE=$(gcloud compute instances describe $INSTANCE_NAME \
  --project=${PROJECT_ID} --format="value(zone)" | sed 's|.*/||')
```

### 2. Check Error Metrics
```bash
# Check current error rate from metrics
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9092/metrics | grep gitpod_gcp_compute_environment_operations_total"

# Check error breakdown by status
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9092/metrics | grep gitpod_gcp_compute_environment_operations_total | grep -v '=\"success\"'"
```

### 3. Identify Error Patterns
```bash
# Get recent error breakdown by operation type
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner.service --since='10 minutes ago' | grep -E 'environment.*error' | head -20"

# Check error distribution by zone
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner.service --since='30 minutes ago' | grep -E 'zone.*error' | head -20"

# Check Cloud Logging for error patterns
gcloud logging read "resource.type=gce_instance AND labels.runner_id=${RUNNER_ID} AND severity>=ERROR" \
  --project=${PROJECT_ID} --limit=20 --format="table(timestamp,severity,textPayload)"
```

### 4. Check GCP API Status
```bash
# Verify GCP service status
curl -s https://status.cloud.google.com/incidents.json | \
  jq '.[] | select(.end == null and (.affected_products[].title | contains("Compute")))'

# Check for widespread GCP issues
gcloud compute operations list --filter="status:RUNNING OR status:PENDING" --limit=10 --project=${PROJECT_ID}

# Check API request metrics
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9092/metrics | grep gitpod_gcp_compute_api_requests_total"
```

### 5. Analyze Specific Error Types

#### Quota Errors
```bash
# Check for quota-related errors
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner.service --since='30 minutes ago' | grep -i 'quota\|limit.*exceeded'"

# Check quota metrics
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9092/metrics | grep gitpod_gcp_compute_zone_quota_status"

# Check current quota usage
gcloud compute project-info describe --project=YOUR_PROJECT | \
  grep -A 20 quotas
```

#### Permission Errors
```bash
# Check for permission-related errors
sudo journalctl -u gitpod-runner.service --since="30 minutes ago" | \
  grep -E "(403|forbidden|permission.*denied)"

# Verify service account permissions
gcloud projects get-iam-policy YOUR_PROJECT \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:YOUR_SERVICE_ACCOUNT"
```

#### Zone Capacity Issues
```bash
# Check for zone capacity errors
sudo journalctl -u gitpod-runner.service --since="30 minutes ago" | \
  grep -i "zone.*capacity\|zone.*unavailable"

# Check zone status
gcloud compute zones list --filter="region:YOUR_REGION" \
  --format="table(name,status,deprecated.state)"
```

### 4. Check Resource Availability
```bash
# Check instance template availability
gcloud compute instance-templates list --filter="name:gitpod*"

# Verify machine type availability in zones
gcloud compute machine-types list --zones=YOUR_ZONES \
  --filter="name:YOUR_MACHINE_TYPE"
```

### 5. Examine API Request Patterns
```bash
# Check API request rate and errors
curl -s http://127.0.0.1:9090/metrics | \
  grep -E "api_requests_total|rate_limit_hits"

# Look for API throttling
sudo journalctl -u gitpod-runner.service --since="30 minutes ago" | \
  grep -E "(throttl|429|rate.*limit)"
```
