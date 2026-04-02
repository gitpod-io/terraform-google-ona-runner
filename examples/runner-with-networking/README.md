# Ona Runner with Networking

This example creates a full Ona runner infrastructure including VPC, DNS, and all required services.

## Prerequisites

Before starting, ensure you have:
- **GCP Project** with billing enabled
- **Terraform** >= 1.3 installed
- **GCP CLI** (`gcloud`) installed
- **Domain Name** with DNS modification capabilities

## Setup Instructions

### 1. Authenticate with GCP

First, authenticate with your GCP account using one of these methods:

**Option A: User Account Authentication (Recommended for getting started)**
```bash
gcloud auth application-default login
```

**Option B: Service Account Authentication (Recommended for production)**
```bash
# Set the path to your service account key file
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account-key.json"
```

Verify your authentication:
```bash
gcloud auth list
gcloud config set project YOUR_PROJECT_ID
```

### 2. Get Runner Credentials from Ona Dashboard

You need to create a runner in the Ona dashboard to obtain the required credentials:

1. **Access Runner Settings**: Navigate to **Settings → Runners** in your [Ona dashboard](https://app.gitpod.io) and click **Set up a new runner**

2. **Configure Runner Details**:
   - **Provider Selection**: Choose **Google Cloud Platform**
   - **Name**: Provide a descriptive name for your runner (e.g., "my-company-gcp-runner")
   - **Region**: Select the GCP region where you'll deploy the runner

3. **Create Runner**: Click **Create** to generate the runner configuration

4. **Copy Credentials**: The system will generate:
   - **Runner ID**: A unique identifier (e.g., "runner-abc123def456")
   - **Runner Token**: An authentication token (starts with "eyJhbGciOiJSUzI1NiIs...")
   
   ⚠️ **Important**: Store the Runner Token securely. You cannot retrieve it again from the dashboard.

For detailed instructions with screenshots, see the [Ona GCP Runner Setup Documentation](https://ona.com/docs/ona/runners/gcp/setup#create-runner-in-ona).

### 3. Configure Terraform Variables

Copy the example configuration:
```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:
```hcl
# Required: GCP Project and Location
project_id     = "your-gcp-project-id"
region         = "us-central1"
zones          = ["us-central1-a", "us-central1-b", "us-central1-c"]

# Required: Runner Configuration (from Ona dashboard)
runner_name    = "my-gitpod-runner"
runner_id      = "runner-abc123def456"        # From Ona dashboard
runner_token   = "eyJhbGciOiJSUzI1NiIs..."     # From Ona dashboard
runner_domain  = "gitpod.example.com"

# Optional: API endpoint (default shown)
api_endpoint   = "https://app.gitpod.io/api"
```

### 4. Deploy the Infrastructure

Initialize and deploy Terraform:
```bash
# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration (typically takes 15-20 minutes)
terraform apply
```

### 5. Configure DNS

After deployment, configure DNS records at your domain registrar:

1. Get the nameservers from Terraform output:
   ```bash
   terraform output dns_ns_records
   ```

2. Update your domain's nameservers at your domain registrar with the provided values

3. Wait for DNS propagation (can take up to 48 hours, typically much faster)

### 6. Verify Deployment

Test the runner health endpoint:
```bash
# Wait a few minutes after DNS propagation
curl https://gitpod.example.com/_health

# Expected response: {"status":"ok"}
```

Check runner status in the Ona dashboard:
- Navigate to **Settings → Runners**
- Verify your runner shows as **Connected** with green status
- Check **Last Seen** timestamp is recent

## Configuration

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `project_id` | GCP project ID | `"my-project-123"` |
| `region` | GCP region | `"us-central1"` |
| `zones` | List of zones | `["us-central1-a", "us-central1-b"]` |
| `runner_name` | Runner identifier | `"my-runner"` |
| `runner_id` | Ona runner ID | `"runner-abc123"` |
| `runner_token` | Runner auth token | `"token-xyz789"` |
| `runner_domain` | Domain for the runner | `"gitpod.example.com"` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `api_endpoint` | Ona API endpoint | `"https://app.gitpod.io/api"` |
| `certificate_id` | Existing certificate ID | `""` (auto-created) |
| `ssh_port` | SSH port for environments | `29222` |
| `development_version` | Development build version | `""` |
| `labels` | Labels to apply to resources | `{}` |
| `proxy_config` | HTTP/HTTPS proxy configuration | `null` |
| `loadbalancer_type` | `external` (default) or `internal` | `"external"` |
| `certificate_secret_id` | Secret Manager cert for internal LB | `""` (auto-created) |
| `enable_certbot` | Enable Let's Encrypt certificate automation | `false` |
| `certbot_email` | Email for Let's Encrypt registration | `""` |

### Internal Load Balancer

Set `loadbalancer_type = "internal"` for a private runner accessible only within the VPC. The module automatically:
- Creates a proxy-only subnet (`REGIONAL_MANAGED_PROXY`) required by the internal TCP proxy LB
- Generates a self-signed TLS certificate and stores it in Secret Manager (unless `certificate_secret_id` is provided or certbot is enabled)

```hcl
loadbalancer_type = "internal"
```

### Automatic Certificate Management (Certbot)

For internal load balancers, you can enable automatic TLS certificate management via Let's Encrypt instead of using a self-signed certificate. This uses a Cloud Run Job with the `certbot/dns-google` image to obtain and renew wildcard certificates using DNS-01 challenges against Cloud DNS.

#### Prerequisites

1. The Cloud Scheduler API (`cloudscheduler.googleapis.com`) must be enabled in your project. The `services` module handles this automatically.
2. A Cloud DNS managed zone for your runner domain (created automatically by this module).
3. NS delegation from your parent DNS zone to the module-created zone (see deployment steps below).

#### Deployment

Certbot uses DNS-01 challenges, which require NS delegation to be in place before the certificate can be issued. Deploy in two steps:

```bash
# Step 1: Create infrastructure (certbot job is created but not triggered)
terraform apply

# Step 2: Set up NS delegation — add NS records in your parent zone
#         pointing to the nameservers from the output:
terraform output dns_ns_records

# Step 3: Verify DNS propagation
dig NS <your-runner-domain>

# Step 4: Trigger certbot to issue the certificate
terraform apply -var run_initial_certbot=true
```

If you already have NS delegation in place (e.g., from a previous deployment), you can combine steps 1 and 4:

```bash
terraform apply -var run_initial_certbot=true
```

#### Configuration

```hcl
loadbalancer_type   = "internal"
enable_certbot      = true
certbot_email       = "your-email@example.com"
run_initial_certbot = true  # set after NS delegation is in place
```

#### What it creates

- **Service account** with least-privilege IAM (DNS admin on the zone, Secret Manager read/write)
- **GCS bucket** for certbot state persistence (renewal tracking, account keys)
- **Cloud Run v2 Job** running `certbot/dns-google` with a GCS FUSE volume mount
- **Cloud Scheduler** job for daily renewal (default: 3am daily, configurable via `schedule` in the certbot module)
- **Secret Manager secret** containing the certificate and private key as JSON

#### How renewal works

1. Cloud Scheduler triggers the Cloud Run Job daily
2. Certbot checks if the certificate needs renewal (within 30 days of expiry)
3. If renewal is needed, certbot obtains a new certificate via DNS-01 challenge and writes it to Secret Manager
4. The proxy VM's `cert-refresh` systemd timer (runs every 5 minutes) detects the new certificate version in Secret Manager and atomically replaces the on-disk files
5. The proxy's TLS hot-reload picks up the new certificate without restart

#### Certificate format in Secret Manager

The certificate is stored as JSON:
```json
{
  "certificate": "-----BEGIN CERTIFICATE-----\n...",
  "privateKey": "-----BEGIN PRIVATE KEY-----\n..."
}
```

## What's Created

- **VPC and Networking**: Complete network setup with subnets and firewall rules (includes proxy-only subnet for internal LB)
- **DNS Zone**: Managed DNS zone for your domain
- **SSL Certificate**: Certificate Manager cert (external LB) or self-signed cert in Secret Manager (internal LB)
- **Runner Infrastructure**: VM instances, load balancer, and all required services

## Outputs

- `load_balancer_ip`: IP address to point your domain to
- `dns_ns_records`: Nameservers to configure at your domain registrar
- `dns_zone_name`: DNS zone name
- `dns_setup_instructions`: Complete setup instructions
- `vpc_name`: Name of the created VPC
- `runner_subnet_name`: Name of the runner subnet
