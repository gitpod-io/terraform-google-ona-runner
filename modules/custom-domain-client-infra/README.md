# Custom Domain Client Infrastructure

This Terraform module deploys the customer-side infrastructure required to connect to Ona via Private Service Connect (PSC) with a custom domain and HTTPS support.

### Custom Domain Request Flow

```
1. Customer Request
   ├─ Header: X-Gitpod-GCP-ID: customer-project-123
   └─ Via: HTTPS → Load Balancer → PSC

2. Relay Receives Request
   ├─ Extracts project ID from header
   └─ Validates project ID against GCP Service Attachment API
      (ensures the project has a valid PSC connection)

3. Validation Result
   ├─ Valid: Forwards request to backend URL
   └─ Invalid: Returns 401 Unauthorized

## Prerequisites

1. **GCP Project** with billing enabled
2. **Application Default Credentials** configured:
   ```bash
   gcloud auth application-default login
   ```
3. **VPC Network** and a routable subnet (Recommend /28 CIDR)
4. **Regional Proxy-only subnet** in your VPC (required for regional HTTPS load balancers)
5. **Regional SSL Certificate** (can be a GCP managed certificate, but must be regional)

## Usage

### 1. Configure Terraform

Copy the example configuration:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
project_id = "your-gcp-project-id"
region     = "us-central1"

vpc_network            = "default"
subnet_name            = "default"

domain_name        = "gitpod.example.com"
certificate_manager_cert_id = "projects/your-gcp-project-id/regions/us-central1/certificates/gitpod-custom-domain-cert"
```

### 2. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

### 3. Configure DNS

After deployment, configure your internal DNS to point your domain to the load balancer IP:

```bash
# Get the load balancer IP
terraform output load_balancer_ip

# Configure DNS (example for Cloud DNS)
gcloud dns record-sets create gitpod.example.com. \
  --zone=your-dns-zone \
  --type=A \
  --ttl=300 \
  --rrdatas="LOAD_BALANCER_IP"
```

### 4. Test Connection

```bash
# Test HTTPS connectivity from within your VPC
curl -v https://gitpod.example.com/

# Check PSC connection status
gcloud compute forwarding-rules describe gitpod-custom-domain-psc \
  --region=us-central1 \
  --format="get(pscConnectionStatus)"
```

## Variables

| Name | Description | Type | Required |
|------|-------------|------|----------|
| `project_id` | GCP project ID | string | Yes |
| `region` | GCP region | string | Yes |
| `vpc_network` | VPC network name | string | No (default: "default") |
| `subnet_name` | Subnet name | string | No (default: "default") |
| `domain_name` | Custom domain name | string | Yes |
| `certificate_manager_cert_id` | GCP regional certificate resource ID | string | Yes |
| `service_name` | Resource name prefix | string | No (default: "gitpod-custom-domain") |

## Outputs

| Name | Description |
|------|-------------|
| `load_balancer_ip` | Internal IP of the HTTPS load balancer |
| `psc_endpoint_ip` | Internal IP of the PSC endpoint |
| `domain_name` | Configured domain name |
| `ssl_certificate_used` | SSL certificate resource ID |
| `connection_instructions` | Setup instructions |
| `psc_connection_status` | PSC connection status |
