# GCP Runner High Disk Usage Runbook

## Alert: GCPRunnerHighDiskUsage

**Severity:** Medium  
**Component:** gcp-runner  
**Alert Type:** resource_usage

## Description

This alert fires when the GCP Runner instance disk usage exceeds 85% for more than 10 minutes. High disk usage can lead to service failures and operational issues.

## Impact

- Risk of disk full conditions
- Potential service failures when disk space is exhausted
- Log rotation issues
- Docker image pull failures
- Prometheus data collection issues

## Investigation Steps

### 1. Check Current Disk Usage

```bash
# Get runner instance details
INSTANCE_NAME=$(gcloud compute instance-groups managed list-instances ${RUNNER_ID}-runner-mig \
  --region=${REGION} --project=${PROJECT_ID} --format="value(instance)" | head -1)

ZONE=$(gcloud compute instances describe $INSTANCE_NAME \
  --project=${PROJECT_ID} --format="value(zone)" | sed 's|.*/||')

# Check current disk usage
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="df -h"

# Check disk metrics from node-exporter
curl -s http://127.0.0.1:9100/metrics | grep node_filesystem_
```

### 2. Identify Large Files and Directories

```bash
# Find largest directories
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo du -h / 2>/dev/null | sort -hr | head -20"

# Check Docker space usage
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo docker system df"

# Check log file sizes
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo find /var/log -type f -size +100M -exec ls -lh {} \;"
```

### 3. Check Specific High-Usage Areas

```bash
# Check Prometheus data directory
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo du -sh /var/lib/prometheus/data"

# Check Docker volumes
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo du -sh /var/lib/docker"

# Check system logs
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo du -sh /var/log"

# Check temporary files
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo du -sh /tmp /var/tmp"
```

### 4. Check Inode Usage

```bash
# Check inode usage (can cause "disk full" even with space available)
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="df -i"

# Find directories with many files
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo find / -type d -exec sh -c 'echo \"{} \$(ls -1 \"{}\" 2>/dev/null | wc -l)\"' \; 2>/dev/null | sort -k2 -nr | head -10"
```

## Resolution Steps

### 1. Clean Docker Resources

```bash
# Remove unused Docker images
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo docker image prune -f"

# Remove unused Docker containers
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo docker container prune -f"

# Remove unused Docker volumes
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo docker volume prune -f"

# Clean all unused Docker resources
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo docker system prune -af"
```

### 2. Clean Log Files

```bash
# Rotate and compress logs
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo logrotate -f /etc/logrotate.conf"

# Clean old journal logs (keep last 7 days)
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl --vacuum-time=7d"

# Clean old log files
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo find /var/log -name '*.log.*' -mtime +7 -delete"
```

### 3. Clean Prometheus Data

```bash
# Check Prometheus retention settings
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo docker logs prometheus 2>&1 | grep retention"

# If needed, reduce Prometheus retention (requires restart)
# Edit the prometheus service file to change --storage.tsdb.retention.time=7d to a smaller value
```

### 4. Clean Temporary Files

```bash
# Clean temporary files
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo find /tmp -type f -mtime +1 -delete"

# Clean package cache
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo apt-get clean" || \
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo yum clean all"
```

### 5. Scale Disk Resources

```bash
# Check current disk size
gcloud compute disks describe $INSTANCE_NAME \
  --zone=$ZONE --project=${PROJECT_ID} --format="value(sizeGb)"

# If needed, resize the disk (requires restart for root partition)
# gcloud compute disks resize $INSTANCE_NAME \
#   --size=50GB --zone=$ZONE --project=${PROJECT_ID}
```

## Prevention

1. **Disk Monitoring**: Implement proactive disk monitoring with lower thresholds
2. **Log Rotation**: Ensure proper log rotation is configured
3. **Docker Cleanup**: Implement automated Docker cleanup jobs
4. **Prometheus Retention**: Configure appropriate Prometheus data retention
5. **Capacity Planning**: Monitor disk usage trends and plan capacity increases

## Related Alerts

- GCPRunnerHighMemoryUsage
- GCPRunnerHighCPUUsage
- GCPRunnerServiceDown

## Escalation

If high disk usage persists:

1. Consider increasing disk size
2. Review log retention policies
3. Implement automated cleanup procedures
4. Consider using separate disks for different data types
5. Escalate to infrastructure team for storage optimization
