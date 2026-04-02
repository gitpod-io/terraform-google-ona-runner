# GCP Runner High CPU Usage Runbook

## Alert: GCPRunnerHighCPUUsage

**Severity:** Medium  
**Component:** gcp-runner  
**Alert Type:** resource_usage

## Description

This alert fires when the GCP Runner instance CPU usage exceeds 80% for more than 10 minutes. High CPU usage can impact performance and response times.

## Impact

- Performance degradation of environment operations
- Slower API response times
- Potential service timeouts
- Reduced throughput for environment creation/management

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

### 1. Check Current CPU Usage

```bash
# Get runner instance details
INSTANCE_NAME=$(gcloud compute instance-groups managed list-instances ${RUNNER_ID}-runner-mig \
  --region=${REGION} --project=${PROJECT_ID} --format="value(instance)" | head -1)

ZONE=$(gcloud compute instances describe $INSTANCE_NAME \
  --project=${PROJECT_ID} --format="value(zone)" | sed 's|.*/||')

# Check current CPU usage
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="top -bn1 | head -20"

# Check CPU metrics from node-exporter
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9100/metrics | grep node_cpu_seconds_total"
```

### 2. Identify High CPU Processes

```bash
# Check top CPU consuming processes
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="ps aux --sort=-%cpu | head -20"

# Check Docker container resource usage
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="docker stats --no-stream"

# Check systemd service CPU usage
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="systemctl status gitpod-runner prometheus node-exporter"
```

### 3. Check System Load

```bash
# Check system load averages
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="uptime"

# Check CPU info
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="lscpu"

# Check memory usage (high memory can cause CPU pressure)
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="free -h"
```

### 4. Check Application Metrics

```bash
# Check runner service metrics
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep gitpod_gcp_runtime_active_goroutines"

# Check for goroutine leaks
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep go_goroutines"

# Check GC metrics
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep go_gc_duration_seconds"
```

## Resolution Steps

### 1. Check for Resource Leaks

```bash
# Check for memory leaks in runner
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner --since='1 hour ago' | grep -i 'memory\|leak\|oom'"

# Check for goroutine leaks using pprof endpoint
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/debug/pprof/goroutine?debug=1 | head -50"
```

### 2. Restart Services if Needed

```bash
# Restart runner service if it's consuming high CPU
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo systemctl restart gitpod-runner"

# Monitor CPU usage after restart
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="watch -n 5 'top -bn1 | head -10'"
```

### 3. Scale Resources

```bash
# Check current machine type
gcloud compute instances describe $INSTANCE_NAME \
  --zone=$ZONE --project=${PROJECT_ID} --format="value(machineType)"

# If needed, resize to larger machine type (requires restart)
# gcloud compute instances set-machine-type $INSTANCE_NAME \
#   --machine-type=n1-standard-4 --zone=$ZONE --project=${PROJECT_ID}
```

### 4. Check for External Load

```bash
# Check API request rate
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep gitpod_gcp_compute_api_requests_total"

# Check environment operation rate
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep gitpod_gcp_compute_environment_operations_total"

# Check for unusual activity patterns
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner.service --since='30 minutes ago' | grep -c 'environment'"
```

## Prevention

1. **Resource Monitoring**: Implement proactive CPU monitoring with lower thresholds
2. **Auto-scaling**: Consider implementing auto-scaling for runner instances
3. **Resource Limits**: Set appropriate resource limits for containers
4. **Performance Testing**: Regular performance testing under load
5. **Capacity Planning**: Monitor trends and plan capacity increases

## Related Alerts

- GCPRunnerHighMemoryUsage
- GCPRunnerHighGoroutineCount
- GCPRunnerHighLatency

## Escalation

If high CPU usage persists:

1. Consider scaling to larger machine type
2. Investigate potential performance regressions in recent deployments
3. Review application code for CPU-intensive operations
4. Consider horizontal scaling with multiple runner instances
5. Escalate to development team for performance optimization
