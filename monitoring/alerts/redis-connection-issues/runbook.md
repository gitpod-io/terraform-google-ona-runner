# GCP Runner Redis Connection Issues Runbook

## Alert: GCPRunnerRedisConnectionIssues

**Severity:** High  
**Component:** gcp-runner  
**Alert Type:** redis_connectivity

## Description

This alert fires when the GCP Runner cannot connect to Redis for more than 2 minutes. Redis is used for environment state management and caching.

## Impact

- Environment state management is degraded
- Potential data consistency issues
- Environment operations may fail or be delayed
- Cache misses affecting performance

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

## Investigation Steps

### 1. Check GCP Runner Service Status

```bash
# Check if runner service is running
gcloud compute instance-groups managed list-instances ${RUNNER_ID}-runner-mig \
  --region=${REGION} --project=${PROJECT_ID}

# Get runner instance details
INSTANCE_NAME=$(gcloud compute instance-groups managed list-instances ${RUNNER_ID}-runner-mig \
  --region=${REGION} --project=${PROJECT_ID} --format="value(instance)" | head -1)

ZONE=$(gcloud compute instances describe $INSTANCE_NAME \
  --project=${PROJECT_ID} --format="value(zone)" | sed 's|.*/||')

# Check runner service status
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo systemctl status gitpod-runner"
```

### 2. Check Redis Connection

```bash
# Check Redis health from runner instance
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner -f --since='10 minutes ago' | grep -i redis"

# Check Redis connectivity manually
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9091/health | jq '.checks[] | select(.name==\"redis\")'"
```

### 3. Check Redis Metrics

```bash
# Check Redis connection health metrics from runner instance
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep gitpod_gcp_compute_redis_connection"

# Check Redis connection error metrics from Prometheus
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9092/metrics | grep gitpod_gcp_compute_redis_connection"

# Check Redis error types and counts
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep gitpod_gcp_compute_redis_connection_errors_total"
```

### 4. Check Network Connectivity

```bash
# Test network connectivity to Redis endpoints
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo netstat -tulpn | grep redis"

# Check DNS resolution
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="nslookup redis-endpoint"
```

## Resolution Steps

### 1. Restart Runner Service

```bash
# Restart the runner service
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo systemctl restart gitpod-runner"

# Monitor service startup
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner -f"
```

### 2. Check Redis Configuration

```bash
# Check Redis configuration in runner
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo docker logs gitpod-runner 2>&1 | grep -i redis | tail -20"
```

### 3. Restart Instance (if needed)

```bash
# If service restart doesn't help, restart the instance
gcloud compute instances stop $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID}
gcloud compute instances start $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID}
```

## Prevention

1. **Monitor Redis Health**: Ensure Redis health checks are running regularly
2. **Network Monitoring**: Monitor network connectivity to Redis endpoints
3. **Resource Monitoring**: Ensure sufficient resources for Redis connections
4. **Configuration Review**: Regularly review Redis connection configuration

## Related Alerts

- GCPRunnerServiceDown
- GCPRunnerHighErrorRate
- GCPRunnerNetworkErrors

## Escalation

If the issue persists after following these steps:

1. Check with the infrastructure team about Redis service status
2. Review recent changes to network configuration
3. Consider scaling Redis resources if connection limits are reached
4. Escalate to the platform team for deeper investigation
