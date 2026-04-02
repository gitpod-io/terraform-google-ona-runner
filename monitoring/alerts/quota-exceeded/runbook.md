# GCP Runner Quota Exceeded

## Alert Description
This alert fires when the GCP Runner hits quota limits in GCP. It monitors:
- `rate(gitpod_gcp_compute_zone_quota_status_total{status="exceeded"}[10m]) > 0`
- Triggers when quota exceeded events are detected over 10 minutes

## Impact
**Medium Impact:** Capacity limitations affecting new environment creation
- Cannot create new environments in affected zones
- Existing environments continue to function normally
- Users may experience delays or failures when starting new workspaces
- Potential need to scale to other zones or increase quotas

## Debugging Steps

### 1. Identify Quota Issues
```bash
# Check quota status metrics
curl -s http://127.0.0.1:9090/metrics | \
  grep zone_quota_status_total

# Look for quota-related errors in logs
sudo journalctl -u gitpod-runner.service --since="30 minutes ago" | \
  grep -i "quota\|limit.*exceeded"
```

### 2. Check Current Quota Usage
```bash
# Get current project quotas
gcloud compute project-info describe --project=YOUR_PROJECT | \
  grep -A 20 quotas

# Check specific quota usage by region
gcloud compute regions describe YOUR_REGION \
  --format="table(quotas.metric,quotas.usage,quotas.limit)"

# Check zone-specific quotas
gcloud compute zones describe YOUR_ZONE \
  --format="table(availableCpuPlatforms)"
```

### 3. Analyze Resource Usage
```bash
# Check current instance usage
gcloud compute instances list --project=YOUR_PROJECT \
  --format="table(name,zone,machineType,status)" | \
  grep YOUR_ZONE

# Check disk usage
gcloud compute disks list --project=YOUR_PROJECT \
  --filter="zone:YOUR_ZONE" \
  --format="table(name,sizeGb,type,status)"

# Check IP address usage
gcloud compute addresses list --project=YOUR_PROJECT \
  --filter="region:YOUR_REGION"
```

### 4. Identify Quota Types
```bash
# Common quota types that may be exceeded:
# - INSTANCES (number of VM instances)
# - CPUS (total CPU cores)
# - DISKS_TOTAL_GB (total disk space)
# - STATIC_ADDRESSES (static IP addresses)
# - IN_USE_ADDRESSES (IP addresses in use)

# Check specific quota metrics in logs
sudo journalctl -u gitpod-runner.service --since="1 hour ago" | \
  grep -E "(INSTANCES|CPUS|DISKS|ADDRESSES).*quota"
```

### 5. Check Historical Usage Patterns
```bash
# Look for usage spikes that led to quota exhaustion
sudo journalctl -u gitpod-runner.service --since="24 hours ago" | \
  grep -E "environment.*create" | \
  awk '{print $1, $2}' | sort | uniq -c

# Check for failed environment creations
sudo journalctl -u gitpod-runner.service --since="24 hours ago" | \
  grep -E "environment.*failed.*quota"
```

### 6. Verify Multi-Zone Distribution
```bash
# Check if other zones are available
gcloud compute zones list --filter="region:YOUR_REGION" \
  --format="table(name,status)"

# Check instance distribution across zones
gcloud compute instances list --project=YOUR_PROJECT \
  --format="table(zone)" | sort | uniq -c
```

## Resolution Steps

### Immediate Actions
1. **Request quota increase** for the affected resource type:
   ```bash
   # Go to GCP Console > IAM & Admin > Quotas
   # Filter by the affected quota type and region/zone
   # Request quota increase
   ```

2. **Scale to other zones** if available:
   ```bash
   # Check available zones in the region
   gcloud compute zones list --filter="region:YOUR_REGION AND status:UP"
   ```

3. **Clean up unused resources** to free quota:
   ```bash
   # List stopped instances that can be deleted
   gcloud compute instances list --filter="status:TERMINATED"
   
   # List unused disks
   gcloud compute disks list --filter="users:*" --format="table(name,zone,users)"
   ```

### Quota Management
1. **Monitor quota usage trends** to predict future needs
2. **Set up quota alerts** in GCP Console for proactive monitoring
3. **Implement resource cleanup policies** for unused resources
4. **Consider regional distribution** to spread load across zones

### Long-term Solutions
1. **Automate quota monitoring** and alerting
2. **Implement resource lifecycle management** 
3. **Plan capacity based on usage patterns**
4. **Consider reserved instances** for predictable workloads

### Escalation
- **Critical quota limits:** Contact GCP support for emergency quota increase
- **Repeated quota issues:** Review resource allocation and cleanup policies
- **Multi-zone failures:** Consider expanding to additional regions
