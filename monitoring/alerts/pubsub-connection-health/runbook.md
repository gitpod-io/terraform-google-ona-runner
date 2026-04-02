# GCP Runner PubSub Connection Health

## Alert: GCPRunnerPubSubConnectionUnhealthy

**Severity:** High  
**Component:** gcp-runner  
**Alert Type:** pubsub_connectivity

## Description

This alert fires when the GCP Runner loses connection to PubSub for more than 2 minutes. PubSub is used for event-driven reconciliation and real-time environment state updates.

## Impact

- Event-driven reconciliation is degraded
- Potential delays in environment state updates
- May fall back to polling-based reconciliation
- Reduced real-time responsiveness

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

### 1. Check PubSub Connection Health

```bash
# Check PubSub connection health metrics
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep gitpod_gcp_pubsub_connection_health"

# Check PubSub subscription status
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep gitpod_gcp_pubsub_subscription_active"
```

### 2. Check PubSub Errors

```bash
# Check PubSub subscription errors
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep gitpod_gcp_pubsub_subscription_errors_total"

# Check runner logs for PubSub errors
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner.service --since='30 minutes ago' | grep -i pubsub"
```

### 3. Test Network Connectivity

```bash
# Test connectivity to PubSub endpoints
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -I https://pubsub.googleapis.com"

# Check DNS resolution
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="nslookup pubsub.googleapis.com"
```

## Resolution Steps

### 1. Restart Runner Service

```bash
# Restart the runner service to re-establish PubSub connection
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo systemctl restart gitpod-runner.service"

# Monitor service startup
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner.service -f"
```

### 2. Check PubSub Subscription Configuration

```bash
# Verify PubSub subscription exists and is configured correctly
gcloud pubsub subscriptions describe ${RUNNER_ID}-subscription --project=${PROJECT_ID}

# Check subscription permissions
gcloud pubsub subscriptions get-iam-policy ${RUNNER_ID}-subscription --project=${PROJECT_ID}
```

### 3. Verify Service Account Permissions

```bash
# Check if service account has PubSub permissions
gcloud projects get-iam-policy ${PROJECT_ID} \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:${RUNNER_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
```

## Prevention

1. **Monitor PubSub Health**: Ensure PubSub health checks are running regularly
2. **Network Monitoring**: Monitor network connectivity to Google APIs
3. **Service Account Monitoring**: Monitor service account permissions and quotas
4. **Subscription Monitoring**: Monitor PubSub subscription configuration

## Related Alerts

- GCPRunnerServiceDown
- GCPRunnerPubSubBacklog
- GCPRunnerNetworkErrors

## Escalation

If the issue persists after following these steps:

1. Check Google Cloud Status page for PubSub service issues
2. Review recent changes to network configuration or firewall rules
3. Verify PubSub quotas and limits
4. Escalate to the platform team for deeper investigation
