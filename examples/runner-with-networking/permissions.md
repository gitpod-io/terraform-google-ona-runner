# Additional Permissions for runner-with-networking Example

This example requires additional permissions beyond the base Terraform service account setup.

## Prerequisites

First, follow the main [Terraform Service Account Permissions](../../docs/terraform_service_account_permissions.md) documentation to create the base service account with core permissions.

## Additional Permissions Required

The `runner-with-networking` example creates additional infrastructure that requires these extra permissions:

### DNS and network Management
- **`roles/dns.admin`** - Creates DNS managed zones, DNS records, and certificate validation records
- **`roles/compute.networkAdmin`** - Creates VPCs, subnets, Cloud Router, Cloud NAT, and firewall rules *(already included above)*
- **`roles/certificatemanager.editor`** - Creates DNS authorizations for certificate validation *(covered by certificatemanager.owner above)*


## Adding the Additional Permission

```bash
# Set your project and service account details
export PROJECT_ID="your-project-id"
export SA_NAME="gitpod-terraform"

# Add DNS admin role
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/dns.admin"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/compute.networkAdmin"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/certificatemanager.editor"
```

## What This Example Creates

**Networking Module:**
- VPC networks and subnets with private Google access
- Cloud Router and Cloud NAT for outbound internet access
- Firewall rules for traffic control

**DNS Module:**
- DNS managed zones for domain management
- Certificate Manager DNS authorizations for SSL certificates
- DNS records for certificate validation

**Main Example:**
- DNS A records for wildcard (`*.domain.com`) and root domain routing

## Note

Most networking permissions are already covered by the existing `roles/compute.admin` role from the base setup. Only DNS management requires the additional specific permission.
