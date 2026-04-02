# Grafana Dashboards

This directory contains Grafana dashboard configurations for monitoring the Ona GCP Runner infrastructure.

## Available Dashboards

### gitpod-runner-overview.json
**Comprehensive operational dashboard** - Complete monitoring solution for the Ona GCP runner infrastructure.

**Dashboard Sections:**
- **Version & Replicas**: Runner version tracking and replica count monitoring
- **Health Status**: Runner health checks and active instance states by lifecycle stage
- **GCP Runner Kit Interface**: Environment operation durations, function calls, and error rates
- **GCP API Operations**: API request metrics, success rates, error rates, and latency heatmaps
- **KV Store Operations**: Redis/key-value store operation rates and durations
- **PubSub Operations**: Message processing, acknowledgments, connection health, and subscription status
- **Environment Operations**: Compute environment operation rates and durations
- **System Metrics**: Host-level CPU, memory, disk usage (%), and disk I/O via node-exporter
- **WRI**: Workspace Runtime Interface performance metrics

**Key Features:**
- Uses Prometheus data source with template variables for filtering
- Template variables: `$project_id`, `$region`, `$runner_name`, `$instance`
- Real-time metrics with 5-minute rate calculations
- Color-coded health indicators and thresholds
- Comprehensive coverage of all infrastructure components
