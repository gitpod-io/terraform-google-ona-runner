# GCP Runner Registry Health

## Alert: GCPRunnerRegistryUnhealthy

**Severity:** Medium  
**Component:** gcp-runner  
**Alert Type:** registry_connectivity

## Description

This alert fires when the GCP Runner detects unhealthy connections to container registries for more than 5 minutes. Registry connectivity is essential for environment creation and image operations.

## Impact

- Container image operations may fail
- Environment creation and updates affected
- Potential delays in workspace startup
- Image cache operations degraded

## Prerequisites

Set up the required environment variables before running debugging commands:

```bash
# Set these variables based on your Terraform deployment
export PROJECT_ID="your-gcp-project-id"
export REGION="your-region"  # e.g., us-central1
export RUNNER_ID="your-runner-id"  # The runner ID from your Terraform configuration

# Get runner instance details
INSTANCE_NAME=$(gcloud compute instance-groups managed list-instances ${RUNNER_ID}-runner-mig \
  --region=${REGION} --project=${PROJECT_ID} --format="value(instance)" | head -1)

ZONE=$(gcloud compute instances describe $INSTANCE_NAME \
  --project=${PROJECT_ID} --format="value(zone)" | sed 's|.*/||')

echo "Instance: $INSTANCE_NAME, Zone: $ZONE"
```

## Investigation Steps

### 1. Check Registry Health Status

```bash
# Check registry health metrics
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep gitpod_gcp_registry_health_status"

# Check registry operation errors
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep gitpod_gcp_registry_errors_total"
```

### 2. Check Registry Authentication

```bash
# Check registry authentication metrics
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep gitpod_gcp_registry_authentication"

# Check for authentication errors in logs
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner.service --since='30 minutes ago' | grep -i 'registry.*auth'"
```

### 3. Test Registry Connectivity

```bash
# Test connectivity to Artifact Registry
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -I https://${REGION}-docker.pkg.dev"

# Test Docker registry operations
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo docker pull hello-world"
```

### 4. Check Registry Configuration

```bash
# Check Docker configuration
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo cat /var/lib/gitpod/docker-config/config.json"

# Check registry credentials
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner.service --since='30 minutes ago' | grep -i 'registry.*credential'"
```

## Resolution Steps

### 1. Restart Registry Services

```bash
# Restart runner service to refresh registry connections
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo systemctl restart gitpod-runner.service"
```

### 2. Verify Registry Permissions

```bash
# Check Artifact Registry permissions
gcloud artifacts repositories get-iam-policy gitpod-cache-${RUNNER_ID} \
  --location=${REGION} --project=${PROJECT_ID}

# Test registry access with service account
gcloud auth activate-service-account --key-file=/path/to/service-account.json
gcloud auth configure-docker ${REGION}-docker.pkg.dev
```

### 3. Check Registry Quotas

```bash
# Check Artifact Registry quotas
gcloud artifacts repositories list --project=${PROJECT_ID} --location=${REGION}

# Check storage usage
gcloud artifacts docker images list ${REGION}-docker.pkg.dev/${PROJECT_ID}/gitpod-cache-${RUNNER_ID} \
  --include-tags --project=${PROJECT_ID}
```

## Prevention

1. **Registry Monitoring**: Monitor registry health and performance
2. **Authentication Monitoring**: Monitor service account permissions and token refresh
3. **Quota Monitoring**: Monitor registry storage and request quotas
4. **Network Monitoring**: Monitor network connectivity to registry endpoints

## Related Alerts

- GCPRunnerServiceDown
- GCPRunnerNetworkErrors
- GCPRunnerHighErrorRate

## Escalation

If registry issues persist:

1. Check Google Cloud Status page for Artifact Registry service issues
2. Review recent changes to registry configuration or permissions
3. Verify network connectivity and firewall rules
4. Contact platform team for registry infrastructure investigation
