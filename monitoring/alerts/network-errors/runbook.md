# GCP Runner Network Errors Runbook

## Alert: GCPRunnerNetworkErrors

**Severity:** Medium  
**Component:** gcp-runner  
**Alert Type:** network_connectivity

## Description

This alert fires when the GCP Runner is experiencing network errors at a rate higher than 0.1 errors per second over 5 minutes. This indicates connectivity issues to external services.

## Impact

- Intermittent connectivity issues affecting environment operations
- Potential delays in API calls to GCP services
- DNS resolution problems
- Reduced reliability of external service calls

## Investigation Steps

### 1. Check Network Error Details

```bash
# Get runner instance details
INSTANCE_NAME=$(gcloud compute instance-groups managed list-instances ${RUNNER_ID}-runner-mig \
  --region=${REGION} --project=${PROJECT_ID} --format="value(instance)" | head -1)

ZONE=$(gcloud compute instances describe $INSTANCE_NAME \
  --project=${PROJECT_ID} --format="value(zone)" | sed 's|.*/||')

# Check network error metrics
curl -s http://127.0.0.1:9092/metrics | grep gitpod_gcp_compute_network_errors_total

# Check network connection health (uses existing gcp_network subsystem with connection_type="health_check")
curl -s http://127.0.0.1:9092/metrics | grep gitpod_gcp_network_connection_health
```

### 2. Check Network Connectivity

```bash
# Test connectivity to key endpoints
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="ping -c 5 8.8.8.8"

# Test DNS resolution
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="nslookup googleapis.com"

# Test HTTPS connectivity
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -I https://googleapis.com"
```

### 3. Check Health Check Status

```bash
# Check overall health status
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9091/health | jq '.checks[] | select(.name | contains(\"network\"))'"

# Check DNS health specifically
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9091/health | jq '.checks[] | select(.name==\"dns_setup\")'"
```

### 4. Check System Network Configuration

```bash
# Check network interfaces
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="ip addr show"

# Check routing table
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="ip route show"

# Check DNS configuration
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="cat /etc/resolv.conf"
```

## Resolution Steps

### 1. Check Service Logs

```bash
# Check runner service logs for network errors
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner --since='10 minutes ago' | grep -i 'network\|dns\|timeout\|connection'"

# Check system network logs
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl --since='10 minutes ago' | grep -i 'network\|dns'"
```

### 2. Restart Network Services

```bash
# Restart systemd-resolved (if DNS issues)
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo systemctl restart systemd-resolved"

# Restart runner service
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo systemctl restart gitpod-runner"
```

### 3. Check GCP Network Configuration

```bash
# Check VPC firewall rules
gcloud compute firewall-rules list --filter="name~${RUNNER_ID}" --project=${PROJECT_ID}

# Check subnet configuration
gcloud compute networks subnets describe ${RUNNER_ID}-subnet \
  --region=${REGION} --project=${PROJECT_ID}

# Check NAT gateway (if using private IPs)
gcloud compute routers nats list --router=${RUNNER_ID}-router \
  --region=${REGION} --project=${PROJECT_ID}
```

### 4. Test Specific Endpoints

```bash
# Test GCP API endpoints
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -I https://compute.googleapis.com"

# Test metadata service
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/"

# Test container registry
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -I https://gcr.io"
```

## Prevention

1. **Network Monitoring**: Implement comprehensive network monitoring
2. **DNS Monitoring**: Monitor DNS resolution times and failures
3. **Firewall Rules**: Regularly review and test firewall rules
4. **Health Checks**: Ensure network health checks are comprehensive
5. **Redundancy**: Consider multiple network paths for critical services

## Related Alerts

- GCPRunnerServiceDown
- GCPRunnerHighLatency
- GCPRunnerDNSIssues

## Escalation

If network errors persist:

1. Check with the network team about infrastructure issues
2. Review recent changes to VPC or firewall configuration
3. Check GCP service status for regional issues
4. Consider temporary failover to different region/zone
5. Escalate to infrastructure team for deeper network analysis
