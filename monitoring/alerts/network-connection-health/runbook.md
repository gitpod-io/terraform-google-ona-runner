# GCP Runner Network Connection Health

## Alert: GCPRunnerNetworkConnectionUnhealthy

**Severity:** Medium  
**Component:** gcp-runner  
**Alert Type:** network_connectivity

## Description

This alert fires when the GCP Runner detects unhealthy network connections to external services for more than 3 minutes.

## Impact

- Potential connectivity issues to external services
- May affect API calls and service functionality
- Could lead to increased latency or timeouts
- May trigger circuit breakers if persistent

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

### 1. Check Network Connection Health

```bash
# Check network connection health metrics
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep gitpod_gcp_network_connection_health"

# Check network connection errors
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep gitpod_gcp_network_connection_errors_total"
```

### 2. Test Connectivity to Key Services

```bash
# Test connectivity to GCP APIs
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -I https://compute.googleapis.com && curl -I https://secretmanager.googleapis.com"

# Test network latency
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="ping -c 5 compute.googleapis.com"

# Check DNS resolution
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="nslookup compute.googleapis.com"
```

### 3. Check Network Configuration

```bash
# Check network interface configuration
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="ip addr show && ip route show"

# Check firewall rules
gcloud compute firewall-rules list --project=${PROJECT_ID} --filter="direction:EGRESS"

# Check if proxy is configured
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="env | grep -i proxy"
```

## Resolution Steps

### 1. Restart Network Services

```bash
# Restart runner service to re-establish connections
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo systemctl restart gitpod-runner.service"
```

### 2. Check Network Policies

```bash
# Verify VPC and subnet configuration
gcloud compute networks describe ${VPC_NAME} --project=${PROJECT_ID}
gcloud compute networks subnets describe ${SUBNET_NAME} --region=${REGION} --project=${PROJECT_ID}
```

### 3. Monitor Connection Recovery

```bash
# Monitor network connection metrics
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="watch -n 5 'curl -s http://127.0.0.1:9090/metrics | grep gitpod_gcp_network_connection_health'"
```

## Prevention

1. **Network Monitoring**: Implement comprehensive network monitoring
2. **Redundancy**: Ensure network path redundancy where possible
3. **Health Checks**: Regular health checks for critical network paths
4. **Alerting**: Proactive alerting on network degradation

## Related Alerts

- GCPRunnerServiceDown
- GCPRunnerHighLatency
- GCPRunnerNetworkErrors

## Escalation

If network issues persist:

1. Check Google Cloud Status page for network service issues
2. Review recent changes to VPC, firewall rules, or routing
3. Contact network team for infrastructure investigation
4. Consider temporary failover if available
