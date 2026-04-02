# GCP Runner Goroutine Panics

## Alert: GCPRunnerGoroutinePanics

**Severity:** Critical  
**Component:** gcp-runner  
**Alert Type:** application_error

## Description

This alert fires immediately when the GCP Runner experiences goroutine panics. Panics indicate serious application errors that could lead to service instability.

## Impact

- Application instability and potential crashes
- Service degradation or complete failure
- Data corruption or inconsistent state
- Requires immediate investigation and potential service restart

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

### 1. Check Panic Metrics and Details

```bash
# Check panic count by goroutine
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep gitpod_gcp_runtime_goroutine_panics_total"

# Check goroutine management metrics
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep gitpod_gcp_runtime_goroutine"
```

### 2. Examine Service Logs for Panic Details

```bash
# Look for panic stack traces in logs
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner.service --since='30 minutes ago' | grep -A 20 -B 5 'panic'"

# Check for recent errors that might have caused panics
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner.service --since='30 minutes ago' | grep -E '(FATAL|ERROR|panic|runtime error)'"

# Check container logs directly
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo docker logs gitpod-runner --since=30m | grep -A 20 -B 5 'panic'"
```

### 3. Check Service Health and Status

```bash
# Check if service is still running
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo systemctl status gitpod-runner.service"

# Check service health endpoint
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9091/health | jq ."

# Check if service is responding to metrics requests
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep up"
```

### 4. Check Resource Constraints

```bash
# Check memory usage (panics often related to OOM)
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="free -h && sudo docker stats --no-stream gitpod-runner"

# Check for memory-related errors
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner.service --since='1 hour ago' | grep -i 'memory\\|oom'"

# Check system resources
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="top -bn1 | head -20"
```

## Resolution Steps

### 1. Immediate Response

```bash
# If service is still running but unstable, restart it
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo systemctl restart gitpod-runner.service"

# Monitor service startup
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner.service -f"
```

### 2. Collect Diagnostic Information

```bash
# Collect full logs for analysis
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner.service --since='2 hours ago' > /tmp/runner-logs.txt"

# Get memory profile if service is running
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/debug/pprof/heap > /tmp/heap-profile.pprof"

# Get goroutine profile
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/debug/pprof/goroutine > /tmp/goroutine-profile.pprof"
```

### 3. Check for Known Issues

```bash
# Check if this is a known issue with the current version
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep gitpod_runner_version"

# Check recent deployments or changes
gcloud logging read "resource.type=gce_instance AND labels.runner_id=${RUNNER_ID}" \
  --project=${PROJECT_ID} --limit=50 --format="table(timestamp,severity,textPayload)"
```

## Prevention

1. **Code Review**: Thorough code review focusing on error handling
2. **Testing**: Comprehensive testing including stress and edge cases
3. **Resource Monitoring**: Monitor memory usage and set appropriate limits
4. **Graceful Error Handling**: Ensure all error paths are handled gracefully
5. **Regular Updates**: Keep dependencies and runtime updated

## Related Alerts

- GCPRunnerServiceDown
- GCPRunnerHighMemoryUsage
- GCPRunnerHighGoroutineCount

## Escalation

Goroutine panics require immediate escalation:

1. **Immediate**: Notify development team with panic details
2. **Urgent**: If panics are recurring, consider rolling back recent changes
3. **Critical**: If service is completely down, implement emergency procedures
4. **Follow-up**: Conduct post-incident review to prevent recurrence

## Additional Resources

- [Go Panic Recovery Best Practices](https://golang.org/doc/effective_go.html#recover)
- [Debugging Go Programs](https://golang.org/doc/gdb)
- [pprof Profiling Guide](https://golang.org/pkg/net/http/pprof/)
