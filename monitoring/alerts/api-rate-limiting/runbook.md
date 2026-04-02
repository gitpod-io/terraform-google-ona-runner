# GCP Runner API Rate Limiting

## Alert Description
This alert fires when the GCP Runner hits Google Cloud API rate limits. It monitors:
- `rate(gitpod_gcp_compute_rate_limit_hits_total[5m]) > 0`
- Triggers when any rate limit hits are detected over 5 minutes

## Impact
**High Impact:** Degraded service performance
- Intermittent failures in environment operations
- Delayed environment creation and management
- Reduced system throughput
- Potential cascading effects if sustained

## Debugging Steps

### 1. Identify Rate Limiting Patterns
```bash
# Check rate limit hit metrics
curl -s http://127.0.0.1:9090/metrics | \
  grep rate_limit_hits_total

# Look for rate limiting in logs
sudo journalctl -u gitpod-runner.service --since="30 minutes ago" | \
  grep -i "rate.limit\|quota.exceeded\|429"
```

### 2. Analyze Request Patterns
```bash
# Check API request rate
curl -s http://127.0.0.1:9090/metrics | \
  grep api_requests_total

# Look for request spikes in logs
sudo journalctl -u gitpod-runner.service --since="1 hour ago" | \
  grep -E "api.*request" | \
  awk '{print $1}' | sort | uniq -c | sort -nr
```

### 3. Check Current Quota Usage
```bash
# Check project quotas
gcloud compute project-info describe --project=YOUR_PROJECT | \
  grep -A 20 quotas

# Check specific API quotas
gcloud logging read 'resource.type="gce_project" AND 
  protoPayload.methodName="compute.instances.insert"' \
  --limit=50 --format=json | \
  jq '.[] | .timestamp' | sort | uniq -c
```

### 4. Identify Affected Operations
```bash
# Check which operations are being rate limited
sudo journalctl -u gitpod-runner.service --since="30 minutes ago" | \
  grep -B2 -A2 "rate.limit\|429"

# Check operation types causing rate limits
sudo journalctl -u gitpod-runner.service --since="30 minutes ago" | \
  grep -E "(instances|disks|networks).*429"
```

### 5. Check Concurrent Operations
```bash
# Check for high concurrency
curl -s http://127.0.0.1:9090/metrics | \
  grep -E "active_goroutines|reconciler_queue_depth"

# Look for operation queuing
sudo journalctl -u gitpod-runner.service --since="30 minutes ago" | \
  grep -E "(concurrent|parallel|batch)"
```
