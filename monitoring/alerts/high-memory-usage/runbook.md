# GCP Runner High Memory Usage Runbook

## Alert: GCPRunnerHighMemoryUsage

**Severity:** Medium  
**Component:** gcp-runner  
**Alert Type:** resource_usage

## Description

This alert fires when the GCP Runner instance memory usage exceeds 85% for more than 10 minutes. High memory usage can lead to OOM kills and service instability.

## Impact

- Risk of out-of-memory (OOM) kills
- Performance degradation due to swapping
- Potential service crashes
- Reduced system responsiveness

## Investigation Steps

### 1. Check Current Memory Usage

```bash
# Get runner instance details
INSTANCE_NAME=$(gcloud compute instance-groups managed list-instances ${RUNNER_ID}-runner-mig \
  --region=${REGION} --project=${PROJECT_ID} --format="value(instance)" | head -1)

ZONE=$(gcloud compute instances describe $INSTANCE_NAME \
  --project=${PROJECT_ID} --format="value(zone)" | sed 's|.*/||')

# Check current memory usage
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="free -h"

# Check memory metrics from node-exporter
curl -s http://127.0.0.1:9100/metrics | grep node_memory_
```

### 2. Identify High Memory Processes

```bash
# Check top memory consuming processes
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="ps aux --sort=-%mem | head -20"

# Check Docker container memory usage
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="docker stats --no-stream"

# Check systemd service memory usage
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="systemctl show gitpod-runner prometheus node-exporter --property=MemoryCurrent"
```

### 3. Check for Memory Leaks

```bash
# Check OOM killer logs
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo dmesg | grep -i 'killed process'"

# Check system logs for memory issues
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl --since='1 hour ago' | grep -i 'memory\|oom'"

# Check swap usage
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="swapon --show"
```

### 4. Check Application Memory Metrics

```bash
# Check Go runtime memory metrics
curl -s http://127.0.0.1:9092/metrics | grep go_memstats

# Check for goroutine count (can indicate memory leaks)
curl -s http://127.0.0.1:9092/metrics | grep go_goroutines

# Check heap size
curl -s http://127.0.0.1:9092/metrics | grep go_memstats_heap_inuse_bytes
```

## Resolution Steps

### 1. Force Garbage Collection

```bash
# Trigger Go garbage collection via debug endpoint
curl -X POST http://127.0.0.1:9092/debug/pprof/gc

# Check memory usage after GC
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="free -h"
```

### 2. Restart High Memory Services

```bash
# Check which service is using most memory
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="ps aux --sort=-%mem | head -5"

# Restart runner service if it's the culprit
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo systemctl restart gitpod-runner"

# Monitor memory usage after restart
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="watch -n 5 'free -h'"
```

### 3. Clear System Caches

```bash
# Clear page cache, dentries and inodes
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo sync && sudo echo 3 > /proc/sys/vm/drop_caches"

# Check memory usage after clearing caches
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="free -h"
```

### 4. Scale Resources

```bash
# Check current machine type and memory
gcloud compute instances describe $INSTANCE_NAME \
  --zone=$ZONE --project=${PROJECT_ID} --format="value(machineType)"

# If needed, resize to larger machine type (requires restart)
# gcloud compute instances set-machine-type $INSTANCE_NAME \
#   --machine-type=n1-standard-4 --zone=$ZONE --project=${PROJECT_ID}
```

### 5. Analyze Memory Usage Patterns

```bash
# Get memory usage breakdown
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="cat /proc/meminfo"

# Check for memory fragmentation
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="cat /proc/buddyinfo"

# Check slab usage
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo slabtop -o"
```

## Prevention

1. **Memory Monitoring**: Implement proactive memory monitoring with lower thresholds
2. **Resource Limits**: Set appropriate memory limits for containers
3. **Memory Profiling**: Regular memory profiling of applications
4. **Capacity Planning**: Monitor memory trends and plan capacity increases
5. **Leak Detection**: Implement automated memory leak detection

## Related Alerts

- GCPRunnerHighCPUUsage
- GCPRunnerHighGoroutineCount
- GCPRunnerServiceDown

## Escalation

If high memory usage persists:

1. Consider scaling to larger machine type with more memory
2. Investigate potential memory leaks in recent deployments
3. Review application code for memory-intensive operations
4. Consider implementing memory limits and monitoring
5. Escalate to development team for memory optimization
