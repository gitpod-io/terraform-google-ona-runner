# GCP Runner High Latency

## Alert Description
This alert fires when GCP Runner environment operations take too long to complete. It monitors:
- `histogram_quantile(0.95, rate(gitpod_gcp_compute_environment_operation_duration_seconds_bucket[5m])) > 300`
- Triggers when 95th percentile latency exceeds 5 minutes

## Impact
**Critical Impact:** Severely degraded user experience
- Slow environment creation (>5 minutes)
- Delayed environment startup times
- Poor developer productivity
- User frustration and potential churn
- SLA breach for environment startup times

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

## Debugging Steps

### 1. Identify Latency Patterns
```bash
# Check current latency metrics from runner service
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep environment_operation_duration_seconds | tail -10"

# Check latency metrics from Prometheus
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9092/metrics | grep environment_operation_duration_seconds | tail -10"

# Analyze latency by operation type from service logs
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner.service --since='30 minutes ago' | grep -E 'operation.*duration' | sort"
```

### 2. Check Zone-Specific Performance
```bash
# Test API latency to different zones from runner instance
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="for zone in us-central1-a us-central1-b us-central1-c; do echo 'Testing zone: \$zone'; time gcloud compute instances list --zones=\$zone --limit=1 --project=${PROJECT_ID}; done"

# Check zone-specific operations in logs
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner.service --since='30 minutes ago' | grep -E 'zone.*duration' | sort"

# Check zone-specific latency metrics
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep 'gitpod_gcp_compute_api_latency_by_zone'"
```

### 3. Analyze GCP API Performance
```bash
# Check API request latency metrics
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep -E 'api_request_duration|api_latency'"

# Look for API throttling or rate limiting in logs
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner.service --since='30 minutes ago' | grep -E '(throttl|429|rate.*limit|backoff)'"

# Check rate limit hit metrics
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep gitpod_gcp_compute_rate_limit_hits_total"
```

### 4. Check Resource Constraints
```bash
# Check runner container resource usage
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo docker stats --no-stream gitpod-runner"

# Check system resource usage
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="free -h && df -h"

# Check CPU and memory usage
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="top -bn1 | head -20"

# Check if runner process is resource constrained
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="ps aux | grep gitpod-runner"
```

### 5. Examine Network Performance
```bash
# Test network latency to GCP APIs from runner instance
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="ping -c 10 compute.googleapis.com"

# Check for network issues with traceroute
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="traceroute compute.googleapis.com"

# Check network connection health metrics
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep gitpod_gcp_network_connection"

# Test HTTPS connectivity to GCP APIs
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -I https://compute.googleapis.com && curl -I https://secretmanager.googleapis.com"
```

### 6. Check Concurrent Operations
```bash
# Check for operation queuing and goroutine metrics
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep -E 'reconciler_queue_depth|active_goroutines|go_goroutines'"

# Check reconciler performance metrics
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep gitpod_gcp_runtime_reconciler"

# Look for operation backlog in logs
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner.service --since='30 minutes ago' | grep -E '(queue|backlog|pending)'"

# Check PubSub backlog which can cause latency
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep gitpod_gcp_pubsub_subscription_backlog"
```
