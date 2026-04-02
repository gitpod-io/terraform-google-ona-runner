# Terraform Service Account Permissions

This document explains the minimal IAM roles required to deploy the Ona GCP Terraform module.

## Option 1: Using pre-defined roles

- **`roles/compute.instanceAdmin.v1`** - Creates VM instances, instance templates, and managed instance groups
- **`roles/compute.networkAdmin`** - Creates load balancers, health checks, backend services, and VPC peering
- **`roles/compute.securityAdmin`** - Creates firewall rules for service isolation
- **`roles/storage.admin`** - Creates GCS buckets for build cache and runner assets
- **`roles/redis.admin`** - Creates Redis instance with private networking
- **`roles/secretmanager.admin`** - Creates secrets for credentials and configuration
- **`roles/pubsub.admin`** - Creates Pub/Sub topics and subscriptions
- **`roles/artifactregistry.admin`** - Creates artifact registry repositories
- **`roles/logging.admin`** - Creates Cloud Logging sinks
- **`roles/cloudkms.admin`** - KMS key management and permissions
- **`roles/certificatemanager.owner`** - Certificate management (includes deletion permissions)
- **`roles/networkconnectivity.admin`** - Permission needed to add PSC setup for redis cluster
- **`roles/servicenetworking.networksAdmin`** - Needed to create redis private connection
- **`roles/cloudkms.admin`** - To create KMS key to encrypt resources
- **`roles/cloudkms.cryptoKeyEncrypterDecrypter`** - To encrypt and decrypt using this KMS key

### High-Privilege Operations (Not needed if using pre-created service accounts)
- **`roles/iam.serviceAccountAdmin`** - Creates service accounts *(skip if using `pre_created_service_accounts`)*
- **`roles/iam.roleAdmin`** - Creates custom IAM roles *(skip if using `pre_created_service_accounts`)*
- **`roles/iam.securityAdmin`** - Sets IAM policies and audit configurations *(skip if using `pre_created_service_accounts`)*
- **`roles/serviceusage.serviceUsageAdmin`** - Enables required GCP APIs *(skip if using `pre_created_service_accounts`)*

### Example-Specific Permissions
Some examples require additional permissions beyond the core set:
- **`examples/runner-with-networking`** - See [permissions.md](../examples/runner-with-networking/permissions.md) for DNS and networking requirements

## Creating the Service Account

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export SA_NAME="gitpod-terraform"

# Create service account
gcloud iam service-accounts create ${SA_NAME} \
    --display-name="Ona Terraform Deployer" \
    --project=${PROJECT_ID}

# Core infrastructure roles (always required)
roles=(
    "roles/compute.admin"
    "roles/iam.serviceAccountUser"
    "roles/resourcemanager.projectIamAdmin"
    "roles/certificatemanager.owner"
    "roles/secretmanager.admin"
    "roles/storage.admin"
    "roles/pubsub.admin"
    "roles/cloudfunctions.admin"
    "roles/serviceusage.serviceUsageAdmin"
    "roles/monitoring.admin"
    "roles/logging.admin"
    "roles/artifactregistry.admin"
    "roles/servicenetworking.networksAdmin"
    "roles/cloudkms.admin"
    "roles/redis.admin"
    "roles/cloudkms.cryptoKeyEncrypterDecrypter"
    "roles/networkconnectivity.admin"
)
    

# High-privilege roles (only needed if NOT using pre-created service accounts)
if [[ "${USE_PRE_CREATED_SA}" != "true" ]]; then
    roles+=(
        "roles/iam.serviceAccountAdmin"
        "roles/iam.roleAdmin"
        "roles/iam.securityAdmin"
        "roles/serviceusage.serviceUsageAdmin"
    )
fi

# Assign roles
for role in "${roles[@]}"; do
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="${role}"
done

# Create service account key
gcloud iam service-accounts keys create terraform-key.json \
    --iam-account="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
```

## Option 2: Custom Role with Minimal Permissions

For restricted environments or when predefined roles are blacklisted, create a custom role with specific permissions.

### Step 1: Create permissions file

Create a file named `permissions.txt` with the following content:

```
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
compute.instances.setMachineType
compute.instances.reset
compute.instances.update
compute.instances.updateNetworkInterface
compute.instances.updateShieldedInstanceConfig
compute.instanceTemplates.create
compute.instanceTemplates.delete
compute.instanceTemplates.get
compute.instanceTemplates.list
compute.instanceTemplates.useReadOnly
compute.instanceTemplates.getIamPolicy
compute.instanceTemplates.setIamPolicy
compute.instanceGroups.create
compute.instanceGroups.delete
compute.instanceGroups.get
compute.instanceGroups.list
compute.instanceGroups.update
compute.instanceGroupManagers.create
compute.instanceGroupManagers.delete
compute.instanceGroupManagers.get
compute.instanceGroupManagers.list
compute.instanceGroupManagers.update
compute.instanceGroupManagers.use
compute.instanceGroups.use
compute.autoscalers.create
compute.autoscalers.delete
compute.autoscalers.get
compute.autoscalers.list
compute.autoscalers.update
compute.disks.create
compute.disks.delete
compute.disks.get
compute.disks.list
compute.disks.setLabels
compute.diskTypes.get
compute.diskTypes.list
compute.images.get
compute.images.list
compute.images.useReadOnly
compute.machineTypes.get
compute.machineTypes.list
compute.zones.get
compute.zones.list
compute.regions.get
compute.regions.list
compute.projects.get
compute.projects.setCommonInstanceMetadata
compute.globalOperations.get
compute.globalOperations.list
compute.regionOperations.get
compute.regionOperations.list
compute.zoneOperations.get
compute.zoneOperations.list
compute.networks.get
compute.networks.list
compute.networks.updatePolicy
compute.subnetworks.get
compute.subnetworks.list
compute.subnetworks.use
compute.addresses.create
compute.addresses.createInternal
compute.addresses.delete
compute.addresses.deleteInternal
compute.addresses.get
compute.addresses.list
compute.addresses.setLabels
compute.addresses.use
compute.globalAddresses.create
compute.globalAddresses.delete
compute.globalAddresses.get
compute.globalAddresses.list
compute.globalAddresses.setLabels
compute.globalAddresses.use
compute.healthChecks.create
compute.healthChecks.delete
compute.healthChecks.get
compute.healthChecks.list
compute.healthChecks.update
compute.healthChecks.use
compute.healthChecks.useReadOnly
compute.regionHealthChecks.create
compute.regionHealthChecks.delete
compute.regionHealthChecks.get
compute.regionHealthChecks.list
compute.regionHealthChecks.update
compute.regionHealthChecks.useReadOnly
compute.backendServices.create
compute.backendServices.delete
compute.backendServices.get
compute.backendServices.list
compute.backendServices.update
compute.backendServices.use
compute.regionBackendServices.create
compute.regionBackendServices.delete
compute.regionBackendServices.get
compute.regionBackendServices.list
compute.regionBackendServices.update
compute.regionBackendServices.use
compute.targetSslProxies.create
compute.targetSslProxies.delete
compute.targetSslProxies.get
compute.targetSslProxies.list
compute.targetSslProxies.update
compute.targetSslProxies.use
compute.targetTcpProxies.create
compute.targetTcpProxies.delete
compute.targetTcpProxies.get
compute.targetTcpProxies.list
compute.targetTcpProxies.update
compute.targetTcpProxies.use
compute.regionTargetTcpProxies.create
compute.regionTargetTcpProxies.delete
compute.regionTargetTcpProxies.get
compute.regionTargetTcpProxies.list
compute.regionTargetTcpProxies.use
compute.forwardingRules.create
compute.forwardingRules.delete
compute.forwardingRules.get
compute.forwardingRules.list
compute.forwardingRules.update
compute.globalForwardingRules.create
compute.globalForwardingRules.delete
compute.globalForwardingRules.get
compute.globalForwardingRules.list
compute.globalForwardingRules.update
compute.firewalls.create
compute.firewalls.delete
compute.firewalls.get
compute.firewalls.list
compute.firewalls.update
compute.sslCertificates.create
compute.sslCertificates.delete
compute.sslCertificates.get
compute.sslCertificates.list
iam.serviceAccounts.create
iam.serviceAccounts.delete
iam.serviceAccounts.get
iam.serviceAccounts.list
iam.serviceAccounts.update
iam.serviceAccounts.getIamPolicy
iam.serviceAccounts.setIamPolicy
iam.serviceAccounts.actAs
iam.serviceAccounts.getAccessToken
iam.roles.create
iam.roles.delete
iam.roles.get
iam.roles.list
iam.roles.update
resourcemanager.projects.get
resourcemanager.projects.getIamPolicy
resourcemanager.projects.setIamPolicy
storage.buckets.create
storage.buckets.delete
storage.buckets.get
storage.buckets.getIamPolicy
storage.buckets.list
storage.buckets.setIamPolicy
storage.buckets.update
storage.objects.create
storage.objects.delete
storage.objects.get
storage.objects.getIamPolicy
storage.objects.list
storage.objects.setIamPolicy
storage.objects.update
secretmanager.secrets.create
secretmanager.secrets.delete
secretmanager.secrets.get
secretmanager.secrets.getIamPolicy
secretmanager.secrets.list
secretmanager.secrets.setIamPolicy
secretmanager.secrets.update
secretmanager.versions.access
secretmanager.versions.add
secretmanager.versions.destroy
secretmanager.versions.disable
secretmanager.versions.enable
secretmanager.versions.get
secretmanager.versions.list
pubsub.topics.create
pubsub.topics.delete
pubsub.topics.get
pubsub.topics.getIamPolicy
pubsub.topics.list
pubsub.topics.publish
pubsub.topics.setIamPolicy
pubsub.topics.update
pubsub.topics.attachSubscription
pubsub.subscriptions.create
pubsub.snapshots.seek
pubsub.subscriptions.delete
pubsub.subscriptions.get
pubsub.subscriptions.getIamPolicy
pubsub.subscriptions.list
pubsub.subscriptions.setIamPolicy
pubsub.subscriptions.update
pubsub.subscriptions.consume
artifactregistry.repositories.create
artifactregistry.repositories.delete
artifactregistry.repositories.get
artifactregistry.repositories.getIamPolicy
artifactregistry.repositories.list
artifactregistry.repositories.setIamPolicy
artifactregistry.repositories.update
artifactregistry.dockerimages.get
artifactregistry.dockerimages.list
artifactregistry.repositories.downloadArtifacts
artifactregistry.repositories.uploadArtifacts
redis.clusters.create
redis.clusters.delete
redis.clusters.get
redis.clusters.list
redis.clusters.update
redis.instances.create
redis.instances.delete
redis.instances.get
redis.instances.list
redis.instances.update
redis.operations.get
redis.operations.list
logging.sinks.create
logging.sinks.delete
logging.sinks.get
logging.sinks.list
logging.sinks.update
logging.logEntries.create
logging.logEntries.list
cloudkms.keyRings.create
cloudkms.keyRings.get
cloudkms.keyRings.getIamPolicy
cloudkms.keyRings.list
cloudkms.keyRings.setIamPolicy
cloudkms.cryptoKeys.create
cloudkms.cryptoKeys.get
cloudkms.cryptoKeys.getIamPolicy
cloudkms.cryptoKeys.list
cloudkms.cryptoKeys.setIamPolicy
cloudkms.cryptoKeys.update
cloudkms.cryptoKeyVersions.create
cloudkms.cryptoKeyVersions.destroy
cloudkms.cryptoKeyVersions.get
cloudkms.cryptoKeyVersions.list
cloudkms.cryptoKeyVersions.restore
cloudkms.cryptoKeyVersions.useToEncrypt
cloudkms.cryptoKeyVersions.useToDecrypt
certificatemanager.certmaps.create
certificatemanager.certmaps.delete
certificatemanager.certmaps.get
certificatemanager.certmaps.list
certificatemanager.certmaps.update
certificatemanager.certmapentries.create
certificatemanager.certmapentries.delete
certificatemanager.certmapentries.get
certificatemanager.certmapentries.list
certificatemanager.certmapentries.update
certificatemanager.certs.get
certificatemanager.certs.list
certificatemanager.certs.use
certificatemanager.certmaps.use
certificatemanager.operations.get
networkconnectivity.serviceConnectionPolicies.create
networkconnectivity.serviceConnectionPolicies.delete
networkconnectivity.serviceConnectionPolicies.get
networkconnectivity.serviceConnectionPolicies.list
networkconnectivity.serviceConnectionPolicies.update
networkconnectivity.operations.get
servicenetworking.services.addPeering
servicenetworking.services.get
serviceusage.services.enable
serviceusage.services.get
serviceusage.services.list
```

### Step 2: Create the custom role and service account

```bash
export PROJECT_ID="your-project-id"
export SA_NAME="gitpod-terraform"

# Create the custom role
gcloud iam roles create gitpod_terraform_deployer \
    --project=${PROJECT_ID} \
    --title="Ona Terraform Deployer" \
    --description="Custom role for deploying Ona infrastructure" \
    --permissions="$(cat permissions.txt | paste -sd ',')"

# Create service account
gcloud iam service-accounts create ${SA_NAME} \
    --display-name="Ona Terraform Deployer" \
    --project=${PROJECT_ID}

# Assign the custom role
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="projects/${PROJECT_ID}/roles/gitpod_terraform_deployer"

# Create service account key
gcloud iam service-accounts keys create terraform-key.json \
    --iam-account="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
```

## Using the Service Account

```bash
# Set credentials
export GOOGLE_APPLICATION_CREDENTIALS="./terraform-key.json"

# Deploy infrastructure
terraform init
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

**Note**: If using pre-created service accounts, configure the `pre_created_service_accounts` variable in your `terraform.tfvars` file (see README.md for details).

## Backend Bucket Permissions

If using a GCS bucket for Terraform state, add the service account to the bucket's IAM policy:

```bash
gsutil iam ch serviceAccount:gitpod-terraform@your-project.iam.gserviceaccount.com:roles/storage.objectAdmin gs://your-backend-bucket
```
