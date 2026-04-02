# GCP Runner Zone Capacity Issues

## Alert Description
This alert fires when a GCP zone becomes unavailable for creating new instances. It monitors:
- `gitpod_gcp_compute_zone_capacity_available == 0`
- Triggers when zone capacity is unavailable for more than 15 minutes

## Impact
**Medium Impact:** Reduced capacity in specific zones
- Cannot create new environments in affected zone
- Potential increased latency if traffic redirected
- Reduced redundancy and fault tolerance
- May affect users in specific geographic regions

## Debugging Steps

### 1. Identify Affected Zones
```bash
# Check zone capacity status
curl -s http://127.0.0.1:9090/metrics | \
  grep zone_capacity_available

# Get zone-specific information from logs
sudo journalctl -u gitpod-runner.service --since="30 minutes ago" | \
  grep -E "zone.*capacity\|zone.*unavailable"
```

### 2. Verify Zone Status with GCP
```bash
# Check zone status directly
gcloud compute zones describe YOUR_AFFECTED_ZONE

# List all zones in region with status
gcloud compute zones list --filter="region:YOUR_REGION" \
  --format="table(name,status,deprecated.state)"
```

### 3. Check for GCP Service Issues
```bash
# Check GCP status page for known issues
curl -s https://status.cloud.google.com/incidents.json | \
  jq '.[] | select(.end == null and (.affected_products[].title | contains("Compute")))'

# Check for maintenance windows
gcloud compute operations list --filter="operationType:maintenance" --limit=10
```

### 4. Test Instance Creation in Zone
```bash
# Test creating a small instance in the affected zone
gcloud compute instances create test-capacity-check \
  --zone=YOUR_AFFECTED_ZONE \
  --machine-type=e2-micro \
  --image-family=ubuntu-2004-lts \
  --image-project=ubuntu-os-cloud \
  --dry-run

# Clean up test instance if created
gcloud compute instances delete test-capacity-check \
  --zone=YOUR_AFFECTED_ZONE --quiet
```

### 5. Check Historical Capacity Patterns
```bash
# Look for capacity patterns in logs
sudo journalctl -u gitpod-runner.service --since=2h | \
  grep -E "zone.*capacity" | \
  awk '{print $1, $NF}' | sort

# Check for recurring capacity issues
sudo journalctl -u gitpod-runner.service --since=24h | \
  grep -E "zone.*unavailable" | \
  awk '{print $NF}' | sort | uniq -c
```

### 6. Verify Alternative Zones
```bash
# Check capacity in other zones in the region
for zone in us-central1-a us-central1-b us-central1-c us-central1-f; do
  echo "Testing zone: $zone"
  gcloud compute instances create test-$zone \
    --zone=$zone --machine-type=e2-micro --dry-run 2>&1 | head -1
done
```
