# IAM Configuration

This document provides a complete reference for all IAM resources required by the Ona GCP Terraform module. It's designed for enterprise environments where **IAM teams** handle high-privilege operations and **deployers** have limited permissions.

## Pre-Requisites Setupa (If Service Accounts are getting precreated)

### 1. Required APIs

The following APIs must be enabled before deployment:

```bash
# Core APIs (always required)
gcloud services enable compute.googleapis.com --project=${PROJECT_ID}
gcloud services enable storage.googleapis.com --project=${PROJECT_ID}
gcloud services enable redis.googleapis.com --project=${PROJECT_ID}
gcloud services enable secretmanager.googleapis.com --project=${PROJECT_ID}
gcloud services enable pubsub.googleapis.com --project=${PROJECT_ID}
gcloud services enable logging.googleapis.com --project=${PROJECT_ID}
gcloud services enable monitoring.googleapis.com --project=${PROJECT_ID}
gcloud services enable cloudtrace.googleapis.com --project=${PROJECT_ID}
gcloud services enable artifactregistry.googleapis.com --project=${PROJECT_ID}
gcloud services enable servicenetworking.googleapis.com --project=${PROJECT_ID}
gcloud services enable serviceusage.googleapis.com --project=${PROJECT_ID}

# Certificate Manager API (only for external load balancer)
gcloud services enable certificatemanager.googleapis.com --project=${PROJECT_ID}

# KMS API (only if using CMEK encryption)
gcloud services enable cloudkms.googleapis.com --project=${PROJECT_ID}
```

### 2. Google Service Identities (CMEK Only)

**Required only if using CMEK encryption (`create_cmek = true` or `kms_key_name` provided)**

⚠️ **When using pre-created service accounts, this step is SKIPPED by Terraform and must be handled by IAM teams.**

These Google-managed service accounts need KMS permissions to encrypt/decrypt resources:

```bash
# Get project number
PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)")

# Create service identities (requires roles/serviceusage.serviceUsageAdmin)
gcloud beta services identity create --service=secretmanager.googleapis.com --project=${PROJECT_ID}
gcloud beta services identity create --service=pubsub.googleapis.com --project=${PROJECT_ID}
gcloud beta services identity create --service=artifactregistry.googleapis.com --project=${PROJECT_ID}

# Note: Storage and Compute service identities are created automatically by Google
```

**Service Identity Emails Created:**
- Secret Manager: `service-${PROJECT_NUMBER}@gcp-sa-secretmanager.iam.gserviceaccount.com`
- Pub/Sub: `service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com`
- Artifact Registry: `service-${PROJECT_NUMBER}@gcp-sa-artifactregistry.iam.gserviceaccount.com`
- Cloud Storage: `service-${PROJECT_NUMBER}@gs-project-accounts.iam.gserviceaccount.com` (auto-created)
- Compute Engine: `service-${PROJECT_NUMBER}@compute-system.iam.gserviceaccount.com` (auto-created)

### 3. KMS Permissions for Google Service Identities (CMEK Only)

**Required only if using CMEK encryption**

⚠️ **When using pre-created service accounts, Google service identities are still created by Terraform, but the deployer needs `roles/cloudkms.admin` to grant KMS permissions.**

```bash
# Set your KMS key
export KMS_KEY="projects/${PROJECT_ID}/locations/${REGION}/keyRings/${KEYRING_NAME}/cryptoKeys/${KEY_NAME}"

# Grant KMS permissions to Google service identities
GOOGLE_SAS=(
    "service-${PROJECT_NUMBER}@gcp-sa-secretmanager.iam.gserviceaccount.com"
    "service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com"
    "service-${PROJECT_NUMBER}@gcp-sa-artifactregistry.iam.gserviceaccount.com"
    "service-${PROJECT_NUMBER}@gs-project-accounts.iam.gserviceaccount.com"
    "service-${PROJECT_NUMBER}@compute-system.iam.gserviceaccount.com"
)

for SA in "${GOOGLE_SAS[@]}"; do
    gcloud kms keys add-iam-policy-binding ${KMS_KEY} \
        --member="serviceAccount:${SA}" \
        --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
done
```

## Custom Roles (High-Privilege IAM Team Operation)

**⚠️ These custom roles require high-privilege access to create and should be handled by IAM teams.**

When using pre-created service accounts, these roles must be created beforehand and assigned to the service accounts.

### 1. Runner Custom Role
- **Role ID**: `{runner_name_underscore}_runner` (e.g., `gcp_2_runner`)
- **Title**: Ona Runner
- **Description**: Minimal permissions for runner infrastructure management

**Permissions** (67 total):
```
# Instance lifecycle management
compute.instances.create
compute.instances.delete
compute.instances.get
compute.instances.list
compute.instances.start
compute.instances.stop
compute.instances.setLabels
compute.instances.setMetadata
compute.instances.setTags
compute.instances.attachDisk
compute.instances.detachDisk
compute.instances.setDiskAutoDelete
compute.instances.setServiceAccount

# Disk management
compute.disks.create
compute.disks.delete
compute.disks.get
compute.disks.list
compute.disks.use
compute.disks.useReadOnly

# Network resources
compute.networks.get
compute.networks.list
compute.networks.use
compute.subnetworks.get
compute.subnetworks.list
compute.subnetworks.use
compute.addresses.create
compute.addresses.delete
compute.addresses.get
compute.addresses.use

# Health check permissions for instance group management
compute.healthChecks.use

# Operations monitoring
compute.globalOperations.get
compute.regionOperations.get
compute.zoneOperations.get

# Machine and disk type info
compute.machineTypes.get
compute.machineTypes.list
compute.diskTypes.get
compute.diskTypes.list

# Image management (VM creation and snapshot reconciler)
compute.images.get
compute.images.list
compute.images.useReadOnly
compute.images.create
compute.images.delete
compute.images.setLabels

# Artifact Registry (container images)
artifactregistry.repositories.get
artifactregistry.repositories.list
artifactregistry.repositories.create
artifactregistry.repositories.delete
artifactregistry.repositories.update
artifactregistry.dockerimages.get
artifactregistry.dockerimages.list
artifactregistry.repositories.downloadArtifacts
artifactregistry.repositories.uploadArtifacts

# Secret Manager (environment secrets)
secretmanager.secrets.create
secretmanager.secrets.delete
secretmanager.secrets.get
secretmanager.secrets.list
secretmanager.secrets.getIamPolicy
secretmanager.secrets.setIamPolicy
secretmanager.versions.access
secretmanager.versions.add
secretmanager.versions.destroy

# Pub/Sub (event processing)
pubsub.subscriptions.get
pubsub.subscriptions.list
pubsub.subscriptions.consume
pubsub.topics.get
pubsub.topics.list

# IAM (service account management)
iam.serviceAccounts.actAs
iam.serviceAccounts.getIamPolicy
iam.serviceAccounts.setIamPolicy
iam.serviceAccounts.getAccessToken

# Instance templates and groups
compute.instanceTemplates.create
compute.instanceTemplates.delete
compute.instanceTemplates.get
compute.instanceTemplates.getIamPolicy
compute.instanceTemplates.list
compute.instanceTemplates.setIamPolicy
compute.instanceTemplates.useReadOnly
compute.instanceGroupManagers.get
compute.instanceGroupManagers.list
compute.instanceGroupManagers.create
compute.instanceGroupManagers.delete
compute.instanceGroupManagers.update
compute.instanceGroups.delete
compute.instanceGroups.list

# Cloud Logging (prebuild log persistence)
logging.logEntries.list
logging.logEntries.create
logging.logs.delete
```

### 2. Secret Manager Custom Role
- **Role ID**: `{runner_name_underscore}_secret_manager` (e.g., `gcp_2_secret_manager`)
- **Title**: Ona Secret Manager
- **Description**: Scoped permissions for environment secret management

**Permissions** (7 total):
```
secretmanager.secrets.create
secretmanager.secrets.delete
secretmanager.secrets.get
secretmanager.secrets.list
secretmanager.versions.access
secretmanager.versions.add
secretmanager.versions.destroy
```

### 3. Proxy VM Custom Role
- **Role ID**: `{runner_name_underscore}_proxy_vm` (e.g., `gcp_2_proxy_vm`)
- **Title**: Ona Proxy VM Minimal
- **Description**: Minimal permissions for Ona proxy VM instances

**Permissions** (7 total):
```
# Basic instance metadata (self-introspection)
compute.instances.get
compute.instances.list

# Network information (proxy functionality)
compute.networks.get
compute.subnetworks.get

# Location awareness
compute.zones.get
compute.regions.get

# Service discovery
compute.projects.get
```

## Google Service Identities (CMEK Only)

When CMEK encryption is enabled (`create_cmek = true`), the module creates Google service identities for various services. These are Google-managed service accounts that need KMS permissions to encrypt/decrypt resources.

### Service Identities Created

1. **Secret Manager Service Identity**
   - **Service**: `secretmanager.googleapis.com`
   - **Email**: `service-{project-number}@gcp-sa-secretmanager.iam.gserviceaccount.com`
   - **Purpose**: Encrypt/decrypt secrets in Secret Manager

2. **Pub/Sub Service Identity**
   - **Service**: `pubsub.googleapis.com`
   - **Email**: `service-{project-number}@gcp-sa-pubsub.iam.gserviceaccount.com`
   - **Purpose**: Encrypt/decrypt Pub/Sub messages and topics

3. **Artifact Registry Service Identity**
   - **Service**: `artifactregistry.googleapis.com`
   - **Email**: `service-{project-number}@gcp-sa-artifactregistry.iam.gserviceaccount.com`
   - **Purpose**: Encrypt/decrypt container images and artifacts

4. **Cloud Storage Service Identity**
   - **Email**: `service-{project-number}@gs-project-accounts.iam.gserviceaccount.com`
   - **Purpose**: Encrypt/decrypt GCS objects (automatically created by Google)

5. **Compute Engine Service Identity**
   - **Email**: `service-{project-number}@compute-system.iam.gserviceaccount.com`
   - **Purpose**: Encrypt/decrypt compute disks (automatically created by Google)

### KMS Permissions for Google Service Identities

All Google service identities receive:
- `roles/cloudkms.cryptoKeyEncrypterDecrypter` on the KMS key

**Note**: These service identities are only created when `create_cmek = true`. When using an existing KMS key (`kms_key_name`), you must manually grant these permissions to the Google service accounts.

## Service Accounts (Pre-Creation Recommended)

**For enterprise deployments, it's recommended that IAM teams pre-create these service accounts and provide them to the Terraform module via the `pre_created_service_accounts` variable. This allows deployers to work with limited permissions.**

If not pre-created, the module will create the following service accounts:

### 1. Runner Service Account
- **Name**: `{runner_name}-runner` (e.g., `gcp-2-runner`)
- **Display Name**: Ona Runner
- **Purpose**: Main orchestrator for managing environment VMs and infrastructure
- **Used By**: Runner control plane container

**Custom Roles**:
- `{runner_name}_runner` (see custom role #1 above)

**Predefined Roles**:
- `roles/cloudtrace.agent` - Cloud Trace integration
- `roles/redis.admin` - Redis instance access
- `roles/certificatemanager.viewer` - Certificate access (external LB only)
- `roles/logging.logWriter` - Write logs to Cloud Logging
- `roles/monitoring.metricWriter` - Write metrics to Cloud Monitoring

**Resource-Specific Access**:
- `roles/secretmanager.secretAccessor` on Redis credentials secret
- `roles/secretmanager.secretAccessor` on runner token secret
- `roles/secretmanager.secretAccessor` on metrics configuration secret
- `roles/secretmanager.secretVersionManager` - Manage secret versions
- `roles/storage.objectViewer` on runner assets bucket
- `roles/iam.serviceAccountTokenCreator` on build cache service account
- `roles/iam.serviceAccountTokenCreator` on secret manager service account
- `roles/pubsub.subscriber` on compute events subscription
- `roles/pubsub.viewer` on dead letter subscription
- `roles/cloudkms.cryptoKeyEncrypterDecrypter` on KMS key (if CMEK is enabled)

### 2. Environment VM Service Account  
- **Name**: `{runner_name}-env-vm` (e.g., `gcp-2-env-vm`)
- **Display Name**: Ona Environment VM
- **Purpose**: Minimal permissions for individual environment VMs
- **Used By**: User workspace VMs

**Custom Roles**: None

**Predefined Roles**:
- `roles/artifactregistry.reader` - Pull container images
- `roles/logging.logWriter` - Write logs
- `roles/monitoring.metricWriter` - Write metrics

**Resource-Specific Access**:
- `roles/cloudkms.cryptoKeyEncrypterDecrypter` on KMS key (if CMEK is enabled)

### 3. Build Cache Service Account
- **Name**: `{runner_name}-build-cache` (e.g., `gcp-2-build-cache`)
- **Display Name**: Ona Build Cache
- **Purpose**: GCS build cache operations
- **Used By**: BuildKit for container image caching

**Custom Roles**: None

**Predefined Roles**:
- `roles/logging.logWriter` - Write logs

**Resource-Specific Access**:
- `roles/storage.objectAdmin` on build cache bucket
- `roles/cloudkms.cryptoKeyEncrypterDecrypter` on KMS key (if CMEK is enabled)

### 4. Secret Manager Service Account
- **Name**: `{runner_name}-secrets` (e.g., `gcp-2-secrets`)
- **Display Name**: Ona Secret Manager
- **Purpose**: Environment-specific secret management
- **Used By**: Runner for managing user secrets

**Custom Roles**: None (uses custom role #2 via impersonation)

**Predefined Roles**:
- `roles/logging.logWriter` - Write logs

**Resource-Specific Access**:
- `roles/cloudkms.cryptoKeyEncrypterDecrypter` on KMS key (if CMEK is enabled)

**Note**: This service account is used via impersonation by the Runner service account

### 5. Pub/Sub Processor Service Account
- **Name**: `{runner_name}-pubsub` (e.g., `gcp-2-pubsub`)
- **Display Name**: Ona Pub/Sub Processor
- **Purpose**: Event-driven reconciliation
- **Used By**: Event processing workflows

**Custom Roles**: None

**Predefined Roles**:
- `roles/logging.logWriter` - Write logs
- `roles/monitoring.metricWriter` - Write metrics

**Resource-Specific Access**:
- `roles/cloudkms.cryptoKeyEncrypterDecrypter` on KMS key (if CMEK is enabled)

**Service Account Usage**:
- Runner can use this service account (`roles/iam.serviceAccountUser`)

### 6. Proxy VM Service Account
- **Name**: `{runner_name}-proxy-vm` (e.g., `gcp-2-proxy-vm`)
- **Display Name**: Ona Proxy VM Service
- **Purpose**: Minimal permissions for proxy functionality
- **Used By**: Proxy VM instances

**Custom Roles**:
- `{runner_name}_proxy_vm` (see custom role #3 above)

**Predefined Roles**:
- `roles/logging.logWriter` - Write logs
- `roles/monitoring.metricWriter` - Write metrics
- `roles/artifactregistry.reader` - Pull container images
- `roles/run.viewer` - Cloud Run service discovery
- `roles/certificatemanager.viewer` - Certificate access (external LB only)
- `roles/secretmanager.secretAccessor` - Access secrets for proxy functionality

**Resource-Specific Access**:
- `roles/secretmanager.secretAccessor` on certificate secret (internal LB only)
- `roles/secretmanager.secretAccessor` on metrics configuration secret
- `roles/storage.objectViewer` on runner assets bucket
- `roles/cloudkms.cryptoKeyEncrypterDecrypter` on KMS key (if CMEK is enabled)

## Manual Creation Commands (For IAM Teams)

⚠️ **Important**: These commands create only the core service accounts and roles. Resource-specific permissions (GCS buckets, secrets, Pub/Sub topics, KMS keys) are automatically managed by the Terraform module and should not be assigned manually.

**Prerequisites**: Set your environment variables:
```bash
export PROJECT_ID="your-project-id"
export RUNNER_NAME="your-runner-name"  # e.g., "gcp-2"
```

### Create Service Accounts

```bash
# 1. Runner service account
gcloud iam service-accounts create ${RUNNER_NAME}-runner \
    --display-name="Ona Runner" \
    --description="Service account for runner infrastructure management" \
    --project=${PROJECT_ID}

# 2. Environment VM service account
gcloud iam service-accounts create ${RUNNER_NAME}-env-vm \
    --display-name="Ona Environment VM" \
    --description="Minimal service account for environment VMs" \
    --project=${PROJECT_ID}

# 3. Build cache service account
gcloud iam service-accounts create ${RUNNER_NAME}-build-cache \
    --display-name="Ona Build Cache" \
    --description="Service account for GCS build cache operations" \
    --project=${PROJECT_ID}

# 4. Secret manager service account
gcloud iam service-accounts create ${RUNNER_NAME}-secrets \
    --display-name="Ona Secret Manager" \
    --description="Service account for environment secret management" \
    --project=${PROJECT_ID}

# 5. Pub/Sub processor service account
gcloud iam service-accounts create ${RUNNER_NAME}-pubsub \
    --display-name="Ona Pub/Sub Processor" \
    --description="Service account for processing Pub/Sub compute events" \
    --project=${PROJECT_ID}

# 6. Proxy VM service account
gcloud iam service-accounts create ${RUNNER_NAME}-proxy-vm \
    --display-name="Ona Proxy VM Service" \
    --description="Service account for Ona proxy VM instances" \
    --project=${PROJECT_ID}
```

### Create Custom Roles

```bash
# Convert runner name to underscore format
RUNNER_NAME_UNDERSCORE=$(echo ${RUNNER_NAME} | tr '-' '_')

# 1. Runner custom role
cat > runner-role.yaml << EOF
title: "Ona Runner"
description: "Minimal permissions for runner infrastructure management"
stage: "GA"
includedPermissions:
- compute.instances.create
- compute.instances.delete
- compute.instances.get
- compute.instances.list
- compute.instances.start
- compute.instances.stop
- compute.instances.setLabels
- compute.instances.setMetadata
- compute.instances.setTags
- compute.instances.attachDisk
- compute.instances.detachDisk
- compute.instances.setDiskAutoDelete
- compute.instances.setServiceAccount
- compute.disks.create
- compute.disks.delete
- compute.disks.get
- compute.disks.list
- compute.disks.use
- compute.networks.get
- compute.networks.list
- compute.networks.use
- compute.subnetworks.get
- compute.subnetworks.list
- compute.subnetworks.use
- compute.addresses.create
- compute.addresses.delete
- compute.addresses.get
- compute.addresses.use
- compute.healthChecks.use
- compute.globalOperations.get
- compute.regionOperations.get
- compute.zoneOperations.get
- compute.machineTypes.get
- compute.machineTypes.list
- compute.diskTypes.get
- compute.diskTypes.list
- compute.images.get
- compute.images.list
- compute.images.useReadOnly
- compute.images.create
- compute.images.delete
- compute.images.setLabels
- artifactregistry.repositories.get
- artifactregistry.repositories.list
- artifactregistry.repositories.create
- artifactregistry.repositories.delete
- artifactregistry.repositories.update
- artifactregistry.dockerimages.get
- artifactregistry.dockerimages.list
- artifactregistry.repositories.downloadArtifacts
- artifactregistry.repositories.uploadArtifacts
- secretmanager.secrets.create
- secretmanager.secrets.delete
- secretmanager.secrets.get
- secretmanager.secrets.list
- secretmanager.secrets.getIamPolicy
- secretmanager.secrets.setIamPolicy
- secretmanager.versions.access
- secretmanager.versions.add
- secretmanager.versions.destroy
- pubsub.subscriptions.get
- pubsub.subscriptions.list
- pubsub.subscriptions.consume
- pubsub.topics.get
- pubsub.topics.list
- iam.serviceAccounts.actAs
- iam.serviceAccounts.getIamPolicy
- iam.serviceAccounts.setIamPolicy
- iam.serviceAccounts.getAccessToken
- compute.instanceTemplates.create
- compute.instanceTemplates.delete
- compute.instanceTemplates.get
- compute.instanceTemplates.getIamPolicy
- compute.instanceTemplates.list
- compute.instanceTemplates.setIamPolicy
- compute.instanceTemplates.useReadOnly
- compute.instanceGroupManagers.get
- compute.instanceGroupManagers.list
- compute.instanceGroupManagers.create
- compute.instanceGroupManagers.delete
- compute.instanceGroupManagers.update
- compute.instanceGroups.delete
- compute.instanceGroups.list
- logging.logEntries.list
- logging.logEntries.create
- logging.logs.delete
EOF

gcloud iam roles create ${RUNNER_NAME_UNDERSCORE}_runner \
    --project=${PROJECT_ID} \
    --file=runner-role.yaml

# 2. Secret manager custom role
cat > secret-manager-role.yaml << EOF
title: "Ona Secret Manager"
description: "Scoped permissions for environment secret management"
stage: "GA"
includedPermissions:
- secretmanager.secrets.create
- secretmanager.secrets.delete
- secretmanager.secrets.get
- secretmanager.secrets.list
- secretmanager.versions.access
- secretmanager.versions.add
- secretmanager.versions.destroy
EOF

gcloud iam roles create ${RUNNER_NAME_UNDERSCORE}_secret_manager \
    --project=${PROJECT_ID} \
    --file=secret-manager-role.yaml

# 3. Proxy VM custom role
cat > proxy-vm-role.yaml << EOF
title: "Ona Proxy VM Minimal"
description: "Minimal permissions for Ona proxy VM instances"
stage: "GA"
includedPermissions:
- compute.instances.get
- compute.instances.list
- compute.networks.get
- compute.subnetworks.get
- compute.zones.get
- compute.regions.get
- compute.projects.get
EOF

gcloud iam roles create ${RUNNER_NAME_UNDERSCORE}_proxy_vm \
    --project=${PROJECT_ID} \
    --file=proxy-vm-role.yaml

# Clean up temporary files
rm -f runner-role.yaml secret-manager-role.yaml proxy-vm-role.yaml
```

### Assign Project-Level Permissions

```bash
# Runner service account - core permissions
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${RUNNER_NAME}-runner@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="projects/${PROJECT_ID}/roles/${RUNNER_NAME_UNDERSCORE}_runner"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${RUNNER_NAME}-runner@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/cloudtrace.agent"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${RUNNER_NAME}-runner@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/redis.admin"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${RUNNER_NAME}-runner@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/redis.dbConnectionUser"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${RUNNER_NAME}-runner@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/logging.logWriter"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${RUNNER_NAME}-runner@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${RUNNER_NAME}-runner@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/monitoring.metricWriter"

# Environment VM service account - minimal permissions
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${RUNNER_NAME}-env-vm@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/artifactregistry.reader"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${RUNNER_NAME}-env-vm@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/logging.logWriter"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${RUNNER_NAME}-env-vm@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/monitoring.metricWriter"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${RUNNER_NAME}-env-vm@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"

# Build cache service account - logging only
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${RUNNER_NAME}-build-cache@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/logging.logWriter"

# Secret manager service account - logging only
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${RUNNER_NAME}-secrets@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/logging.logWriter"

# Pub/Sub processor service account - logging and monitoring
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${RUNNER_NAME}-pubsub@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/logging.logWriter"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${RUNNER_NAME}-pubsub@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/monitoring.metricWriter"

# Proxy VM service account - proxy functionality
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${RUNNER_NAME}-proxy-vm@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="projects/${PROJECT_ID}/roles/${RUNNER_NAME_UNDERSCORE}_proxy_vm"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${RUNNER_NAME}-proxy-vm@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/logging.logWriter"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${RUNNER_NAME}-proxy-vm@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/monitoring.metricWriter"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${RUNNER_NAME}-proxy-vm@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${RUNNER_NAME}-proxy-vm@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/artifactregistry.reader"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${RUNNER_NAME}-proxy-vm@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/run.viewer"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${RUNNER_NAME}-proxy-vm@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"
```

⚠️ **Note**: Resource-specific permissions (GCS buckets, secrets, Pub/Sub topics, KMS keys, etc.) are automatically handled by the Terraform module and should not be assigned manually. The above commands only cover project-level role assignments.

## Alternative: Predefined Roles Instead of Custom Roles

If your organization does not allow custom IAM roles, you can skip the "Create Custom Roles" section above and instead grant predefined roles. These roles include more permissions than needed — see the comments on each command for what is required vs excess.

The custom role bindings in the "Assign Project-Level Permissions" section that reference `projects/${PROJECT_ID}/roles/...` should be replaced with the predefined role bindings below. All other bindings (predefined roles like `roles/cloudtrace.agent`, `roles/redis.admin`, etc.) remain unchanged.

### Quick Reference

Project-level roles that need to be manually assigned via the GCP Console or `gcloud`. Roles marked ★ replace a custom role. Resource-specific bindings (buckets, secrets, KMS keys, service accounts) are omitted — Terraform manages those automatically.

| Service Account | Role | Replaces Custom Role |
|---|---|---|
| **`${RUNNER_NAME}-runner`** | `roles/compute.instanceAdmin` | ★ Runner |
| | `roles/compute.storageAdmin` | ★ Runner |
| | `roles/artifactregistry.admin` | ★ Runner |
| | `roles/secretmanager.admin` | ★ Runner |
| | `roles/logging.admin` | ★ Runner |
| | `roles/pubsub.subscriber` | ★ Runner |
| | `roles/pubsub.viewer` | ★ Runner |
| | `roles/iam.serviceAccountUser` | ★ Runner |
| | `roles/cloudtrace.agent` | |
| | `roles/redis.admin` | |
| | `roles/redis.dbConnectionUser` | |
| | `roles/logging.logWriter` | |
| | `roles/monitoring.metricWriter` | |
| | `roles/secretmanager.secretVersionManager` | |
| **`${RUNNER_NAME}-env-vm`** | `roles/artifactregistry.reader` | |
| | `roles/logging.logWriter` | |
| | `roles/monitoring.metricWriter` | |
| **`${RUNNER_NAME}-build-cache`** | `roles/logging.logWriter` | |
| **`${RUNNER_NAME}-secrets`** | `roles/secretmanager.admin` | ★ Secret Manager |
| | `roles/logging.logWriter` | |
| **`${RUNNER_NAME}-pubsub`** | `roles/logging.logWriter` | |
| | `roles/monitoring.metricWriter` | |
| **`${RUNNER_NAME}-proxy-vm`** | `roles/compute.viewer` | ★ Proxy VM |
| | `roles/logging.logWriter` | |
| | `roles/monitoring.metricWriter` | |
| | `roles/artifactregistry.reader` | |
| | `roles/run.viewer` | |
| | `roles/secretmanager.secretAccessor` | |

### Runner Custom Role → Predefined Roles

Replace the single runner custom role binding with these 8 predefined roles:

```bash
export SA="${RUNNER_NAME}-runner@${PROJECT_ID}.iam.gserviceaccount.com"

# Compute instance, disk, network, template, and MIG management.
# Needed: 37 compute permissions for VM lifecycle, disks, networks, operations,
#   machine/disk types, instance templates, and MIG updates.
# Excess: grants 228 additional permissions including autoscaler, network endpoint
#   group, and machine image management that the runner does not use.
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${SA}" \
  --role="roles/compute.instanceAdmin"

# Compute image create, delete, and label management.
# Needed: images.create, images.delete, images.setLabels
# Excess: grants 143 additional permissions including full disk/snapshot admin.
# Note: these 3 permissions are not in roles/compute.instanceAdmin.
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${SA}" \
  --role="roles/compute.storageAdmin"

# Artifact Registry repository lifecycle management.
# Needed: repositories.get, .list, .create, .delete, .update,
#   dockerimages.get, .list, .downloadArtifacts, .uploadArtifacts
# Excess: grants 56 additional permissions including setIamPolicy,
#   deleteArtifacts, and full package/tag/version/rule management.
# Note: repositories.create, .delete, .update only exist in this admin role.
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${SA}" \
  --role="roles/artifactregistry.admin"

# Secret lifecycle and version management.
# Needed: secrets.create, .delete, .get, .list, versions.access, .add,
#   .destroy, .get, .list
# Excess: grants 18 additional permissions including secrets.setIamPolicy,
#   secrets.update, versions.disable/.enable, and KMS-related permissions.
# Note: secrets.create and secrets.delete only exist in this admin role.
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${SA}" \
  --role="roles/secretmanager.admin"

# Log reading, writing, and deletion.
# Needed: logEntries.list, logEntries.create, logs.delete
# Excess: grants 77 additional permissions including full logging infrastructure
#   management (sinks, buckets, exclusions, metrics, views, settings).
# Note: logs.delete only exists in this admin role.
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${SA}" \
  --role="roles/logging.admin"

# Pub/Sub event consumption.
# Needed: subscriptions.consume
# Excess: grants 2 additional permissions (snapshots.seek, topics.attachSubscription).
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${SA}" \
  --role="roles/pubsub.subscriber"

# Pub/Sub subscription existence check.
# Needed: subscriptions.get
# Excess: grants 27 additional read-only Pub/Sub permissions.
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${SA}" \
  --role="roles/pubsub.viewer"

# Assign environment VM service account when creating instances.
# Needed: serviceAccounts.actAs
# Excess: grants 4 additional read-only permissions (get, list, projects.get/list).
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${SA}" \
  --role="roles/iam.serviceAccountUser"
```

### Secret Manager Custom Role → Predefined Role

Replace the single secret manager custom role binding with 1 predefined role:

```bash
export SA="${RUNNER_NAME}-secrets@${PROJECT_ID}.iam.gserviceaccount.com"

# Secret lifecycle and version management.
# Needed: secrets.create, .delete, .get, .list, versions.access, .add, .destroy
# Excess: grants 20 additional permissions including secrets.setIamPolicy,
#   secrets.getIamPolicy, secrets.update, versions.disable/.enable/.get/.list,
#   and KMS-related permissions.
# Note: secrets.create and secrets.delete only exist in this admin role.
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${SA}" \
  --role="roles/secretmanager.admin"
```

### Proxy VM Custom Role → Predefined Role

Replace the single proxy VM custom role binding with 1 predefined role:

```bash
export SA="${RUNNER_NAME}-proxy-vm@${PROJECT_ID}.iam.gserviceaccount.com"

# List compute instances to discover environment VMs by label.
# Needed: instances.list (for AggregatedList API)
# Excess: grants 394 additional read-only compute permissions. All excess is
#   read-only (get/list on all compute resource types).
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${SA}" \
  --role="roles/compute.viewer"
```
