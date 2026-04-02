# GCP Runner Service Down

## Alert Description
This alert fires when the GCP Runner service becomes unavailable. It monitors two key health indicators:
- `up{job="gcp_runner"} == 0` - Runner daemon service is down
- `up{job="gcp_auth_proxy"} == 0` - Auth proxy service is down

## Impact
**Critical Impact:** Complete service outage affecting all users
- Users cannot create new environments
- Users cannot start, stop, or manage existing environments
- All development workflows are blocked
- Immediate SLA breach for environment availability

## Prerequisites

Before running the debugging commands, set up the required environment variables:

```bash
# Set these variables based on your Terraform deployment
export PROJECT_ID="your-gcp-project-id"
export REGION="your-region"  # e.g., us-central1
export RUNNER_ID="your-runner-id"  # The runner ID from your Terraform configuration

# Verify the variables are set
echo "Project: $PROJECT_ID, Region: $REGION, Runner: $RUNNER_ID"
```

You can find these values in your Terraform configuration or by checking the deployed resources:
```bash
# Find runner instance groups
gcloud compute instance-groups managed list --project=$PROJECT_ID --filter="name~runner"

# Find the runner ID from instance group name (format: {runner-id}-runner-mig)
gcloud compute instance-groups managed list --project=$PROJECT_ID --format="value(name)" | grep runner-mig
```

## Debugging Steps

### 1. Get Instance Information
```bash
# Get runner instance details
INSTANCE_NAME=$(gcloud compute instance-groups managed list-instances ${RUNNER_ID}-runner-mig \
  --region=${REGION} --project=${PROJECT_ID} --format="value(instance)" | head -1)

ZONE=$(gcloud compute instances describe $INSTANCE_NAME \
  --project=${PROJECT_ID} --format="value(zone)" | sed 's|.*/||')

echo "Runner instance: $INSTANCE_NAME in zone: $ZONE"
```

### 2. Check Service Status
```bash
# Check if services are running
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo systemctl status gitpod-runner.service"

gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo systemctl status gitpod-auth-proxy.service"

# Check service details and recent failures
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo systemctl show gitpod-runner.service --property=ActiveState,SubState,Result"
```

### 3. Examine Service Logs
```bash
# Check recent logs for errors
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner.service --since='30 minutes ago' --no-pager"

gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-auth-proxy.service --since='30 minutes ago' --no-pager"

# Look for specific error patterns
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo journalctl -u gitpod-runner.service --since='30 minutes ago' | grep -E '(FATAL|ERROR|panic)'"

# Check Cloud Logging for additional context
gcloud logging read "resource.type=gce_instance AND labels.runner_id=${RUNNER_ID}" \
  --project=${PROJECT_ID} --limit=50 --format="table(timestamp,severity,textPayload)"
```

### 4. Check Docker Container Status
```bash
# Check if containers are running
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo docker ps | grep -E '(gitpod-runner|gitpod-auth-proxy)'"

# Check container resource usage
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo docker stats --no-stream gitpod-runner gitpod-auth-proxy"

# Check container logs directly
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo docker logs gitpod-runner --tail=50"

gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo docker logs gitpod-auth-proxy --tail=50"
```

### 4. Verify GCP Connectivity
```bash
# Test GCP API access from within the runner container
sudo docker exec gitpod-runner gcloud compute instances list --project=YOUR_PROJECT --limit=1

# Check if metadata service is accessible
curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token

# Test basic network connectivity
ping -c 3 compute.googleapis.com
```

### 5. Check Service Account Permissions
```bash
# Verify service account has required permissions
gcloud projects get-iam-policy YOUR_PROJECT \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:YOUR_SERVICE_ACCOUNT"
```

### 6. Verify Network Connectivity
```bash
# Test network connectivity to GCP APIs
ping -c 5 compute.googleapis.com
ping -c 5 secretmanager.googleapis.com

# Check DNS resolution
nslookup compute.googleapis.com
nslookup secretmanager.googleapis.com

# Test HTTPS connectivity
curl -I https://compute.googleapis.com
curl -I https://secretmanager.googleapis.com
```

### 7. Check Configuration and Environment
```bash
# Check environment variables passed to containers
sudo systemctl show gitpod-runner.service --property=Environment
sudo systemctl show gitpod-auth-proxy.service --property=Environment

# Check runner environment file
sudo cat /var/lib/gitpod/runner.env

# Verify important directories and files
sudo ls -la /var/lib/gitpod/
sudo ls -la /var/lib/prometheus/
```

### 8. Check Metrics Endpoints
```bash
# Check runner health endpoint
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9091/health | jq ."

# Check auth-proxy health endpoint (auth-proxy runs on port 4430, no separate health endpoint)
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s -k https://127.0.0.1:4430/health || echo 'Auth proxy may not have separate health endpoint'"

# Check Prometheus metrics (port 9092 for Prometheus server)
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9092/metrics | grep prometheus_build_info"

# Check runner metrics (port 9090 for runner service metrics)
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep gitpod_runner_version"

# Check auth-proxy metrics (port 9094 for auth-proxy metrics)
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9094/metrics | grep up"

# Check if all service ports are listening
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo netstat -tlnp | grep -E '(9090|9091|9092|9094|4430|8080)'"
```
