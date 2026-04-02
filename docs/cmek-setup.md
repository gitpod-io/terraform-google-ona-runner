# CMEK Setup for Organizational Policy Compliance

When your organization enforces `constraints/gcp.restrictNonCmekServices`, all GCP resources must use Customer-Managed Encryption Keys (CMEK).

## Option 1: Automatic CMEK Creation (Recommended)

The module can automatically create and manage KMS resources for you.

### Use with Terraform

Add to your `terraform.tfvars`:

```hcl
create_cmek = true
```

Then deploy:

```bash
terraform apply
```

**That's it!** The module will:
- ✅ Create KMS keyring and key
- ✅ Enable required APIs
- ✅ Create service identities
- ✅ Grant all necessary permissions
- ✅ Use the key for all encrypted resources

## Option 2: Use Existing KMS Key

If you have an existing KMS key or want to manage it separately:

### 1. Create KMS Key

```bash
# Set your project and region
PROJECT_ID="your-project-id"
REGION="us-central1"

# Create keyring and key
gcloud kms keyrings create gitpod-keyring --location=$REGION --project=$PROJECT_ID
gcloud kms keys create gitpod-key --keyring=gitpod-keyring --location=$REGION --purpose=encryption --project=$PROJECT_ID
```

### 2. Enable APIs and Create Service Identities

```bash
# Enable required APIs
gcloud services enable secretmanager.googleapis.com pubsub.googleapis.com artifactregistry.googleapis.com storage.googleapis.com compute.googleapis.com cloudkms.googleapis.com --project=$PROJECT_ID

# Create service identities (required for CMEK)
gcloud beta services identity create --service=secretmanager.googleapis.com --project=$PROJECT_ID
gcloud beta services identity create --service=pubsub.googleapis.com --project=$PROJECT_ID  
gcloud beta services identity create --service=artifactregistry.googleapis.com --project=$PROJECT_ID
```

### 2. Create KMS Key

```bash
# Set your project and region
PROJECT_ID="verdant-catcher-465914-i1"
REGION="us-central1"

# Create keyring and key
gcloud kms keyrings create gitpod-keyring --location=$REGION --project=$PROJECT_ID
gcloud kms keys create gitpod-key --keyring=gitpod-keyring --location=$REGION --purpose=encryption --project=$PROJECT_ID
```


### 3. Grant KMS Permissions

```bash
# Get project number
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

# Grant KMS access to Google service accounts
for service in gcp-sa-secretmanager gcp-sa-pubsub gs-project-accounts gcp-sa-artifactregistry compute-system; do
  gcloud kms keys add-iam-policy-binding gitpod-key \
    --keyring=gitpod-keyring \
    --location=$REGION \
    --member=serviceAccount:service-$PROJECT_NUMBER@$service.iam.gserviceaccount.com \
    --role=roles/cloudkms.cryptoKeyEncrypterDecrypter \
    --project=$PROJECT_ID
done
```

### 4. Use with Terraform

Add to your `terraform.tfvars`:

```hcl
create_cmek = false
kms_key_name = "projects/your-project-id/locations/us-central1/keyRings/gitpod-keyring/cryptoKeys/gitpod-key"
```

Then deploy:

```bash
terraform apply
```

## Troubleshooting

**Service account doesn't exist**: Run the service identity creation commands above.

**Permission denied**: Verify KMS permissions were granted to all service accounts.

**Secret already exists**: Import existing secrets:
```bash
terraform import module.runner.google_secret_manager_secret.SECRET_NAME projects/PROJECT_NUMBER/secrets/SECRET_NAME
```

**VMs not starting**: Check serial console logs and ensure Compute Engine service account has KMS access.
