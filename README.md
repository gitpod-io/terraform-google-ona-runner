# Ona GCP Runner

[![Build with Ona](https://gitpod.io/button/open-in-gitpod.svg)](https://gitpod.io/#https://github.com/gitpod-io/terraform-google-ona-runner)

This Terraform module deploys an Ona runner on Google Cloud Platform (GCP).
Refer to [the Ona.com documentation](https://ona.com/docs/ona/runners/gcp/overview)
in order to get started using this module.

## Prerequisites

1. **GCP Project**: A GCP project with billing enabled
2. **Existing Infrastructure**: VPC, subnet, and SSL certificate
3. **SSL Certificate**: A managed certificate in Certificate Manager for your domain
4. **Terraform**: Version >= 1.3
5. **GCP CLI**: For authentication and project setup

## Pre-Created Service Accounts

By default, the module creates 6 service accounts with minimal permissions. If your organization requires pre-created service accounts, you can provide them:

```hcl
pre_created_service_accounts = {
  runner           = "my-runner@my-project.iam.gserviceaccount.com"
  environment_vm   = "my-env-vm@my-project.iam.gserviceaccount.com"
  build_cache      = "my-build-cache@my-project.iam.gserviceaccount.com"
  secret_manager   = "my-secrets@my-project.iam.gserviceaccount.com"
  pubsub_processor = "my-pubsub@my-project.iam.gserviceaccount.com"
  proxy_vm         = "my-proxy-vm@my-project.iam.gserviceaccount.com"
}
```

**Important**: When using pre-created service accounts:
- You must create the required custom IAM roles manually
- You must assign the proper permissions to each service account
- See [IAM Documentation](./docs/iam.md) for complete details

**Partial Configuration**: You can provide some service accounts and let Terraform create others:
```hcl
pre_created_service_accounts = {
  runner = "existing-runner@my-project.iam.gserviceaccount.com"
  # Others will be created by Terraform (leave empty or omit)
}
```

## Customer-Managed Encryption Keys (CMEK)

If your organization requires CMEK encryption for compliance with organizational policies like `constraints/gcp.restrictNonCmekServices`, see the [CMEK Setup Guide](./docs/cmek-setup.md).

**Automatic setup** (recommended):
```hcl
# Add to terraform.tfvars:
create_cmek = true
```

**Manual setup**:
```hcl
# Create KMS key manually (see docs/cmek-setup.md), then:
create_cmek = false
kms_key_name = "projects/your-project/locations/us-central1/keyRings/ona-keyring/cryptoKeys/ona-key"
```

## Module Architecture

This module creates the Ona runner infrastructure using your existing VPC and certificate:

- **Load Balancer**: Global HTTPS load balancer with SSL termination
- **Compute**: Auto-scaling VM instances for runner and proxy services
- **Security**: IAM roles, service accounts, and network security

## Runner with Networking Example

For a full infrastructure setup including VPC, DNS, and certificates, see the [runner-with-networking example](./examples/runner-with-networking/).

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
| `vpc_name` | Existing VPC name | `"my-vpc"` |
| `runner_subnet_name` | Existing subnet name | `"my-subnet"` |
| `certificate_id` | Certificate resource ID | `"projects/.../certificates/..."` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `api_endpoint` | Ona API endpoint | `"https://app.gitpod.io/api"` |
| `ssh_port` | SSH port for environments | `29222` |
| `development_version` | Development build version | `""` |
| `labels` | Labels to apply to resources | `{}` |
| `proxy_config` | HTTP/HTTPS proxy configuration | `null` |


### Internal Load Balancer

To use an internal load balancer instead of the default external load balancer:

```hcl
loadbalancer_type        = "internal"
routable_subnet_name     = "your-routable-subnet"
certificate_secret_id    = "projects/your-project/secrets/your-cert-secret"
```

**Requirements:**
- `routable_subnet_name`: Subnet where the load balancer IP will be allocated
- `certificate_secret_id`: Secret Manager secret containing certificate data in JSON format:
  ```json
  {
    "certificate": "-----BEGIN CERTIFICATE-----...",
    "privateKey": "-----BEGIN PRIVATE KEY-----..."
  }
  ```
- VPC must include a subnet with purpose `REGIONAL_MANAGED_PROXY` for the proxy service

## Examples

- **[Runner with Networking](./examples/runner-with-networking/)**: Full setup with VPC, DNS, and certificates

## Monitoring

The module includes:
- **Prometheus**: Metrics collection on port 9090
- **Health Checks**: Automated health monitoring
- **Logging**: Centralized logging to Cloud Logging

## Security

- All VMs use minimal IAM permissions
- Network traffic is restricted by firewall rules
- SSL/TLS encryption for all external traffic
- Secrets stored in Secret Manager
- CA certificates stored securely in GCS with controlled access

## Release Notifications

Ona publishes Pub/Sub messages when new stable GCP runner releases are available. You can subscribe from your own GCP project to receive notifications instead of polling.

See the [Release Notifications Guide](./docs/release-notifications.md) for topic details, message format, and Terraform/gcloud subscription examples.

## CA Certificate Management

The module supports custom CA certificates for proxy environments:

### Configuration Options

1. **File-based approach** (recommended for CI/CD):
   ```hcl
   ca_certificate = {
     file_path = "/path/to/ca-certificate.pem"
     content   = ""
   }
   ```

2. **Direct content approach**:
   ```hcl
   ca_certificate = {
     file_path = ""
     content   = "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----"
   }
   ```

### How it works

1. **Upload**: CA certificate is uploaded to a dedicated GCS bucket during terraform apply
2. **Download**: VMs download the CA certificate from GCS during startup
3. **Usage**: CA certificate is used by Docker daemon and other tools requiring custom trust
4. **Security**: Access to CA bucket is restricted via IAM to only runner and proxy VMs

## Troubleshooting

### Common Issues

1. **DNS not resolving**: Check domain configuration
2. **Certificate errors**: Ensure certificate is valid and accessible
3. **VM startup failures**: Check Cloud Logging for detailed error messages

### Debugging

```bash
# Check VM logs
gcloud logging read "resource.type=gce_instance" --limit=50

# Check load balancer health
gcloud compute backend-services get-health <backend-service-name>
```
