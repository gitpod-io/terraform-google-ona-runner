# GCP Runner Monitoring Alerts

This directory contains comprehensive monitoring alerts and runbooks for the GCP Runner service. Each alert is organized in its own folder with both the alert definition (YAML) and corresponding runbook (Markdown).

The alerts are organized in a flat structure with 19 different alert types covering critical service monitoring, performance monitoring, and operational health checks.

## Directory Structure

```
alerts/
├── api-rate-limiting/           # High: API rate limiting issues
├── circuit-breaker-open/        # High: Circuit breaker protection active
├── goroutine-panics/            # Critical: Application panics detected
├── high-cpu-usage/              # Medium: High CPU utilization
├── high-disk-usage/             # Medium: High disk utilization
├── high-error-rate/             # Critical: High operation failure rate
├── high-goroutine-count/        # Info: High goroutine count
├── high-latency/                # Critical: High operation latency
├── high-memory-usage/           # Medium: High system memory utilization
├── high-process-memory-usage/   # Info: High process memory usage
├── network-connection-health/   # Medium: Network connectivity issues
├── network-errors/              # Medium: Network error rate
├── pubsub-backlog/              # High: PubSub message backlog
├── pubsub-connection-health/    # High: PubSub connectivity issues
├── quota-exceeded/              # Medium: GCP quota limits reached
├── redis-connection-issues/     # High: Redis connectivity problems
├── registry-health/             # Medium: Container registry issues
├── service-down/                # Critical: Service unavailable
└── zone-capacity-issues/        # Medium: GCP zone capacity problems
```

## Alert Priority Levels

### Critical (Immediate Response Required)
**Impact:** Service outage or severe degradation  
**Escalation:** Page on-call engineer immediately

- **Service Down** - GCP Runner service completely unavailable
- **High Error Rate** - >10% of environment operations failing
- **High Latency** - 95th percentile operation time >5 minutes
- **Goroutine Panics** - Application panics detected (immediate alert)

### High (Prompt Attention Required)
**Impact:** Degraded performance or functionality  
**Escalation:** Notify team via Slack/email

- **API Rate Limiting** - Hitting GCP API rate limits
- **PubSub Backlog** - >1000 unprocessed messages
- **PubSub Connection Health** - PubSub connectivity issues
- **Circuit Breaker Open** - Circuit breaker protecting system
- **Redis Connection Issues** - Redis connectivity problems

### Medium (Monitor and Track)
**Impact:** Reduced capacity or resource constraints  
**Escalation:** Create ticket and notify team

- **High CPU Usage** - CPU usage >80% for extended period
- **High Memory Usage** - Memory usage >80% for extended period
- **High Disk Usage** - Disk usage >85% for extended period
- **Network Connection Health** - Network connectivity issues
- **Network Errors** - High rate of network errors
- **Registry Health** - Container registry connectivity issues
- **Zone Capacity Issues** - GCP zone unavailable
- **Quota Exceeded** - GCP resource quotas hit limits

### Info (Optimization Opportunities)
**Impact:** Performance optimization needed  
**Escalation:** Create improvement ticket

- **High Memory Usage** - Memory usage >1GB for extended period
- **High Goroutine Count** - >1000 active goroutines

## Prerequisites for Using Runbooks

Before using any runbook, set up the required environment variables:

```bash
# Set these variables based on your Terraform deployment
export PROJECT_ID="your-gcp-project-id"
export REGION="your-region"  # e.g., us-central1
export RUNNER_ID="your-runner-id"  # The runner ID from your Terraform configuration

# Verify the variables are set
echo "Project: $PROJECT_ID, Region: $REGION, Runner: $RUNNER_ID"
```

You can find these values from your Terraform deployment:

```bash
# Find runner instance groups
gcloud compute instance-groups managed list --project=$PROJECT_ID --filter="name~runner"

# Find the runner ID from instance group name (format: {runner-id}-runner-mig)
gcloud compute instance-groups managed list --project=$PROJECT_ID --format="value(name)" | grep runner-mig
```

## Using These Alerts

### Grafana Import
Each alert folder contains an `alert.yaml` file that can be imported into Grafana:

1. Navigate to Grafana → Alerting → Alert Rules
2. Click "Import" 
3. Upload the `alert.yaml` file from the desired alert folder (e.g., `service-down/alert.yaml`)
4. Configure notification channels as needed

### Alert Configuration
All alerts use Prometheus metrics from the GCP Runner services. The services run on GCE VM instances with the following port configuration:

- **Runner Service:** Port 8080 (main service), Port 9090 (metrics), Port 9091 (health)
- **Auth Proxy:** Port 4430 (main service), Port 9094 (metrics)
- **Prometheus:** Port 9092 (server)
- **Node Exporter:** Port 9100 (system metrics)

Prometheus scrape configuration (from cloud-init):
```yaml
scrape_configs:
  - job_name: "gcp_runner"
    static_configs:
      - targets: ["localhost:9090"]
  - job_name: "gcp_auth_proxy"
    static_configs:
      - targets: ["localhost:9094"]
  - job_name: "node-exporter"
    static_configs:
      - targets: ["localhost:9100"]
```

### Infrastructure Overview
The GCP Runner is deployed as:
- **Platform:** Google Compute Engine VM instances
- **Container Runtime:** Docker (not Kubernetes)
- **Service Management:** systemd services
- **Service Names:** `gitpod-runner.service`, `gitpod-auth-proxy.service`
- **Instance Group:** Managed Instance Group for auto-scaling and updates

### Runbook Usage
Each alert folder contains a `runbook.md` file with:
- Prerequisites section with environment variable setup
- Alert description and impact assessment
- Step-by-step debugging procedures using `gcloud compute ssh` commands
- Resolution steps and escalation procedures

Example: `service-down/runbook.md` contains comprehensive troubleshooting steps for when the GCP Runner service becomes unavailable.

## Customization

### Thresholds
Adjust alert thresholds based on your environment:
- **Small deployments:** May need lower thresholds
- **Large deployments:** May need higher thresholds
- **Development environments:** May want less sensitive alerts

### Notification Channels
Configure notification channels in Grafana:
- **Critical alerts:** PagerDuty, SMS, phone calls
- **High alerts:** Slack, email
- **Medium/Info alerts:** Email, ticket creation

### Environment Variables
Set these environment variables before using runbooks:
- `PROJECT_ID` → Your GCP project ID (from Terraform)
- `REGION` → Your primary GCP region (from Terraform)
- `RUNNER_ID` → Your runner ID (from Terraform configuration)

The runbooks will automatically derive:
- `INSTANCE_NAME` → Current runner instance name
- `ZONE` → Instance zone location

## Alert Dependencies

### Required Metrics
These alerts depend on the following metrics being exposed:
- `up{job="gcp_runner"}` (runner daemon service health)
- `up{job="gcp_auth_proxy"}` (auth proxy service health)
- `gitpod_gcp_compute_environment_operations_total`
- `gitpod_gcp_compute_environment_operation_duration_seconds`
- `gitpod_gcp_compute_rate_limit_hits_total`
- `gitpod_gcp_pubsub_subscription_backlog_messages`
- `gitpod_gcp_compute_circuit_breaker_state`
- `gitpod_gcp_compute_zone_capacity_available`
- `gitpod_gcp_compute_zone_quota_status_total`
- `process_resident_memory_bytes{job="gcp_runner"}` (standard Go metric)
- `go_goroutines{job="gcp_runner"}` (standard Go metric)

### Service Dependencies
- **Prometheus** for metrics collection (port 9092)
- **Grafana** for alerting (or compatible alerting system)
- **GCP Runner Daemon** service with metrics endpoint enabled (port 9090)
- **GCP Runner Auth Proxy** service with metrics endpoint enabled (port 9094)
- **Container-Optimized OS** with systemd services: `gitpod-runner.service`, `gitpod-auth-proxy.service`

## Testing Alerts

### Simulation
Test alerts by temporarily creating conditions on the runner instance:

```bash
# Set up environment variables first
export PROJECT_ID="your-project-id"
export REGION="your-region"
export RUNNER_ID="your-runner-id"

# Get instance details
INSTANCE_NAME=$(gcloud compute instance-groups managed list-instances ${RUNNER_ID}-runner-mig \
  --region=${REGION} --project=${PROJECT_ID} --format="value(instance)" | head -1)
ZONE=$(gcloud compute instances describe $INSTANCE_NAME \
  --project=${PROJECT_ID} --format="value(zone)" | sed 's|.*/||')

# Test service down alert
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo systemctl stop gitpod-runner.service"
# Wait for alert, then restore
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="sudo systemctl start gitpod-runner.service"

# Check current metrics
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --project=${PROJECT_ID} \
  --command="curl -s http://127.0.0.1:9090/metrics | grep process_resident_memory_bytes"
```

### Validation
Verify alerts are working:
1. Check alert appears in Grafana
2. Verify notification is sent
3. Confirm alert clears when condition resolves
