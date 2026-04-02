

# Data source to get project number for Google service account names
data "google_project" "current" {
  project_id = var.project_id
}

# Local value for the KMS key to use (either created or provided)
locals {
  kms_key_name = var.create_cmek ? google_kms_crypto_key.gitpod[0].id : var.kms_key_name
}

# ================================
# GOOGLE SERVICE IDENTITIES FOR CMEK
# ================================

# Create service identities when CMEK is enabled AND not using pre-created service accounts
resource "google_project_service_identity" "secretmanager" {
  count    = var.create_cmek && !local.using_pre_created_service_accounts ? 1 : 0
  provider = google-beta
  project  = var.project_id
  service  = "secretmanager.googleapis.com"
}

resource "google_project_service_identity" "pubsub" {
  count    = var.create_cmek && !local.using_pre_created_service_accounts ? 1 : 0
  provider = google-beta
  project  = var.project_id
  service  = "pubsub.googleapis.com"
}

resource "google_project_service_identity" "artifactregistry" {
  count    = var.create_cmek && !local.using_pre_created_service_accounts ? 1 : 0
  provider = google-beta
  project  = var.project_id
  service  = "artifactregistry.googleapis.com"
}

resource "google_project_service_identity" "redis" {
  count    = var.create_cmek && !local.using_pre_created_service_accounts ? 1 : 0
  provider = google-beta
  project  = var.project_id
  service  = "redis.googleapis.com"
}

# Grant KMS permissions to Google service accounts when CMEK is enabled AND not using pre-created service accounts
resource "google_kms_crypto_key_iam_member" "google_secretmanager" {
  count = var.create_cmek ? 1 : 0

  crypto_key_id = google_kms_crypto_key.gitpod[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-secretmanager.iam.gserviceaccount.com"
}

resource "google_kms_crypto_key_iam_member" "google_pubsub" {
  count = var.create_cmek ? 1 : 0

  crypto_key_id = google_kms_crypto_key.gitpod[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_kms_crypto_key_iam_member" "google_storage" {
  count = var.create_cmek ? 1 : 0

  crypto_key_id = google_kms_crypto_key.gitpod[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@gs-project-accounts.iam.gserviceaccount.com"
}

resource "google_kms_crypto_key_iam_member" "google_artifactregistry" {
  count = var.create_cmek ? 1 : 0

  crypto_key_id = google_kms_crypto_key.gitpod[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-artifactregistry.iam.gserviceaccount.com"
}

resource "google_kms_crypto_key_iam_member" "google_compute" {
  count = var.create_cmek ? 1 : 0

  crypto_key_id = google_kms_crypto_key.gitpod[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@compute-system.iam.gserviceaccount.com"
}

resource "google_kms_crypto_key_iam_member" "google_redis" {
  count = var.create_cmek ? 1 : 0

  crypto_key_id = google_kms_crypto_key.gitpod[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@cloud-redis.iam.gserviceaccount.com"
}

# 1. RUNNER SERVICE ACCOUNT
# Manages runner infrastructure with minimal permissions
resource "google_service_account" "runner" {
  count = var.pre_created_service_accounts.runner == "" ? 1 : 0

  account_id   = "${var.runner_name}-runner"
  display_name = "Ona Runner"
  description  = "Service account for runner infrastructure management"
  project      = var.project_id
}

# Custom role with minimal compute permissions for runner
resource "google_project_iam_custom_role" "runner" {
  count = var.pre_created_service_accounts.runner == "" ? 1 : 0

  role_id     = "${replace(var.runner_name, "-", "_")}_runner"
  title       = "Ona Runner"
  description = "Minimal permissions for runner infrastructure management"
  project     = var.project_id

  permissions = [
    # Instance lifecycle management
    "compute.instances.create",
    "compute.instances.delete",
    "compute.instances.get",
    "compute.instances.list",
    "compute.instances.start",
    "compute.instances.stop",
    "compute.instances.setLabels",
    "compute.instances.setMetadata",
    "compute.instances.setTags",
    "compute.instances.attachDisk",
    "compute.instances.detachDisk",
    "compute.instances.setDiskAutoDelete",
    "compute.instances.setServiceAccount",

    # Disk management
    "compute.disks.create",
    "compute.disks.delete",
    "compute.disks.get",
    "compute.disks.list",

    # Network resources
    "compute.networks.get",
    "compute.networks.list",
    "compute.networks.use",
    "compute.subnetworks.get",
    "compute.subnetworks.list",
    "compute.subnetworks.use",
    "compute.addresses.create",
    "compute.addresses.delete",
    "compute.addresses.get",
    "compute.addresses.use",

    # Firewall permissions removed - all firewall rules are managed via Terraform
    # No dynamic firewall operations are performed by the orchestrator

    # Health check permissions for instance group management
    "compute.healthChecks.use",

    # Operations monitoring
    "compute.globalOperations.get",
    "compute.regionOperations.get",
    "compute.zoneOperations.get",

    # Machine type and disk type info
    "compute.machineTypes.get",
    "compute.machineTypes.list",
    "compute.diskTypes.get",
    "compute.diskTypes.list",

    # Image management for VM creation and snapshot reconciler
    "compute.images.get",
    "compute.images.list",
    "compute.images.useReadOnly",
    "compute.images.create",
    "compute.images.delete",
    "compute.images.setLabels",

    # Required for creating images from disks (snapshot reconciler)
    "compute.disks.use",
    "compute.disks.useReadOnly",

    # Artifact Registry permissions for devcontainer image cache (minimal)
    "artifactregistry.repositories.get",
    "artifactregistry.repositories.list",
    "artifactregistry.repositories.create",
    "artifactregistry.repositories.delete",
    "artifactregistry.repositories.update",
    "artifactregistry.dockerimages.get",
    "artifactregistry.dockerimages.list",

    "artifactregistry.repositories.downloadArtifacts",
    "artifactregistry.repositories.uploadArtifacts",

    # Secret Manager permissions for environment secrets
    "secretmanager.secrets.create",
    "secretmanager.secrets.delete",
    "secretmanager.secrets.get",
    "secretmanager.secrets.list",
    "secretmanager.secrets.getIamPolicy",
    "secretmanager.secrets.setIamPolicy",
    "secretmanager.versions.access",
    "secretmanager.versions.add",
    "secretmanager.versions.destroy",

    # Pub/Sub permissions for event-driven reconciliation
    "pubsub.subscriptions.get",
    "pubsub.subscriptions.list",
    "pubsub.subscriptions.consume",
    "pubsub.topics.get",
    "pubsub.topics.list",

    # IAM permissions for service account management
    "iam.serviceAccounts.actAs",
    "iam.serviceAccounts.getIamPolicy",
    "iam.serviceAccounts.setIamPolicy",
    "iam.serviceAccounts.getAccessToken",

    # Instance template permissions for runner control plane
    "compute.instanceTemplates.create",
    "compute.instanceTemplates.delete",
    "compute.instanceTemplates.get",
    "compute.instanceTemplates.getIamPolicy",
    "compute.instanceTemplates.list",
    "compute.instanceTemplates.setIamPolicy",
    "compute.instanceTemplates.useReadOnly",

    "compute.instanceGroupManagers.get",
    "compute.instanceGroupManagers.list",
    "compute.instanceGroupManagers.create",
    "compute.instanceGroupManagers.delete",
    "compute.instanceGroupManagers.update",

    # Instance group permissions required for MIG operations
    "compute.instanceGroups.delete",
    "compute.instanceGroups.list",

    # Cloud Logging permissions for environment and prebuild log persistence
    "logging.logEntries.list",   # Read environment logs from Cloud Logging
    "logging.logEntries.create", # Write prebuild logs to Cloud Logging
    "logging.logs.delete",       # Delete prebuild logs when prebuild is deleted
  ]
}

# Bind custom role to runner control plane
resource "google_project_iam_member" "runner_cp_custom_role" {
  count = !local.using_pre_created_service_accounts && local.runner_sa_email != "" ? 1 : 0

  project = var.project_id
  role    = var.pre_created_service_accounts.runner == "" ? google_project_iam_custom_role.runner[0].id : "projects/${var.project_id}/roles/${replace(var.runner_name, "-", "_")}_runner"
  member  = "serviceAccount:${local.runner_sa_email}"

  depends_on = [
    google_project_iam_custom_role.runner,
    google_service_account.runner
  ]
}

# Essential permissions for runner control plane (consolidated logging and monitoring below)

resource "google_project_iam_member" "runner_cp_trace" {
  count = !local.using_pre_created_service_accounts && local.runner_sa_email != "" ? 1 : 0

  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${local.runner_sa_email}"
}

# Redis access for IAM authentication and state management
resource "google_project_iam_member" "runner_cp_redis_editor" {
  count   = !local.using_pre_created_service_accounts && local.runner_sa_email != "" ? 1 : 0
  project = var.project_id
  role    = "roles/redis.editor" # Can read/write but not manage instance
  member  = "serviceAccount:${local.runner_sa_email}"
}

# Additional permission needed for IAM authentication to Redis Cluster
resource "google_project_iam_member" "runner_cp_redis_db_connection" {
  count   = !local.using_pre_created_service_accounts && local.runner_sa_email != "" ? 1 : 0
  project = var.project_id
  role    = "roles/redis.dbConnectionUser" # Required for IAM authentication
  member  = "serviceAccount:${local.runner_sa_email}"
}

# Certificate Manager viewer role for external LB certificate access
resource "google_project_iam_member" "runner_cp_certificate_manager" {
  count   = !local.using_pre_created_service_accounts && local.runner_sa_email != "" && var.loadbalancer_type == "external" ? 1 : 0
  project = var.project_id
  role    = "roles/certificatemanager.viewer"
  member  = "serviceAccount:${local.runner_sa_email}"
}

# Secret Manager access for internal LB certificate secret
resource "google_secret_manager_secret_iam_member" "runner_cp_certificate_secret_access" {
  count     = var.certificate_secret_id != "" ? 1 : 0
  project   = var.project_id
  secret_id = split("/", var.certificate_secret_id)[3]
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.runner_sa_email}"
}

# GCS access for runner assets bucket (runner VMs)
resource "google_storage_bucket_iam_member" "runner_runner_assets_access" {
  bucket = google_storage_bucket.runner_assets.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${local.runner_sa_email}"
}

# GCS access for agent storage bucket (runner VMs)
resource "google_storage_bucket_iam_member" "runner_agent_storage_access" {
  count = var.enable_agents ? 1 : 0

  bucket = google_storage_bucket.agent_storage[0].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${local.runner_sa_email}"
}

# 2. ENVIRONMENT VM SERVICE ACCOUNT
# Minimal permissions for individual environment VMs
resource "google_service_account" "environment_vm" {
  count = var.pre_created_service_accounts.environment_vm == "" ? 1 : 0

  account_id   = "${var.runner_name}-env-vm"
  display_name = "Ona Environment VM"
  description  = "Minimal service account for environment VMs"
  project      = var.project_id
}

# Minimal permissions for environment VMs
resource "google_project_iam_member" "env_vm_artifact_registry" {
  count   = !local.using_pre_created_service_accounts && local.environment_vm_sa_email != "" ? 1 : 0
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${local.environment_vm_sa_email}"
}

# Logging and monitoring permissions consolidated below

# 3. BUILD CACHE SERVICE ACCOUNT
# Dedicated for GCS build cache operations
resource "google_service_account" "build_cache" {
  count = var.pre_created_service_accounts.build_cache == "" ? 1 : 0

  account_id   = "${var.runner_name}-build-cache"
  display_name = "Ona Build Cache"
  description  = "Service account for GCS build cache operations"
  project      = var.project_id
}

# Logging permissions consolidated below

# Allow runner to generate tokens for build cache service account
resource "google_service_account_iam_member" "runner_generate_build_cache_tokens" {
  count              = !local.using_pre_created_service_accounts && local.runner_sa_email != "" ? 1 : 0
  service_account_id = local.build_cache_sa_name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${local.runner_sa_email}"
}

# 4. SECRET MANAGEMENT SERVICE ACCOUNT
# For environment-specific secrets with scoped access
resource "google_service_account" "secret_manager" {
  count = var.pre_created_service_accounts.secret_manager == "" ? 1 : 0

  account_id   = "${var.runner_name}-secrets"
  display_name = "Ona Secret Manager"
  description  = "Service account for environment secret management"
  project      = var.project_id
}

# Logging permissions consolidated below

# Custom role for secret management
resource "google_project_iam_custom_role" "secret_manager" {
  count = var.pre_created_service_accounts.secret_manager == "" ? 1 : 0

  role_id     = "${replace(var.runner_name, "-", "_")}_secret_manager"
  title       = "Ona Secret Manager"
  description = "Scoped permissions for environment secret management"
  project     = var.project_id

  permissions = [
    "secretmanager.secrets.create",
    "secretmanager.secrets.delete",
    "secretmanager.secrets.get",
    "secretmanager.secrets.list",
    "secretmanager.versions.access",
    "secretmanager.versions.add",
    "secretmanager.versions.destroy"
  ]
}

# Allow runner to generate tokens for secret manager
resource "google_service_account_iam_member" "runner_generate_secret_tokens" {
  count              = !local.using_pre_created_service_accounts && local.runner_sa_email != "" ? 1 : 0
  service_account_id = local.secret_manager_sa_name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${local.runner_sa_email}"
}

# Allow runner control plane to access the Redis credentials secret
resource "google_secret_manager_secret_iam_member" "runner_cp_redis_secret_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.redis_auth.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.runner_sa_email}"
}

# Allow runner to destroy secret versions (for cost optimization)
resource "google_project_iam_member" "runner_secret_version_manager" {
  project = var.project_id
  role    = "roles/secretmanager.secretVersionManager"
  member  = "serviceAccount:${local.runner_sa_email}"
}

# 5. PUB/SUB EVENT PROCESSING SERVICE ACCOUNT
# For event-driven reconciliation
resource "google_service_account" "pubsub_processor" {
  count = var.pre_created_service_accounts.pubsub_processor == "" ? 1 : 0

  account_id   = "${var.runner_name}-pubsub"
  display_name = "Ona Pub/Sub Processor"
  description  = "Service account for processing Pub/Sub compute events"
  project      = var.project_id
}

# Logging and monitoring permissions consolidated below

# Allow runner to use Pub/Sub processor for event handling
resource "google_service_account_iam_member" "runner_use_pubsub_processor" {
  count              = !local.using_pre_created_service_accounts && local.runner_sa_email != "" ? 1 : 0
  service_account_id = local.pubsub_processor_sa_name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${local.runner_sa_email}"
}

# RUNNER TOKEN SECRET MANAGER RESOURCE
# Create a secret for storing the runner token securely
resource "google_secret_manager_secret" "runner_token" {
  secret_id = "${var.runner_name}-runner-token"
  project   = var.project_id

  labels = merge(var.labels, {
    purpose = "runner-authentication"
    type    = "api-token"
  })

  replication {
    dynamic "user_managed" {
      for_each = local.kms_key_name != null ? [1] : []
      content {
        replicas {
          location = var.region
          customer_managed_encryption {
            kms_key_name = local.kms_key_name
          }
        }
      }
    }

    dynamic "auto" {
      for_each = local.kms_key_name == null ? [1] : []
      content {}
    }
  }


}

# Create initial secret version with actual join token
resource "google_secret_manager_secret_version" "runner_token_initial" {
  secret = google_secret_manager_secret.runner_token.id

  # Store the actual join token provided via Terraform variable
  secret_data = jsonencode({
    join_token = var.runner_token
    created_by = "terraform"
  })

  lifecycle {
    ignore_changes = [secret_data]
  }
}

# Allow runner control plane to access its own authentication token
resource "google_secret_manager_secret_iam_member" "runner_token_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.runner_token.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.runner_sa_email}"
}

# Allow runner to access metrics configuration secret
resource "google_secret_manager_secret_iam_member" "runner_metrics_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.metrics.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.runner_sa_email}"
}

# Allow proxy VM to access metrics configuration secret
resource "google_secret_manager_secret_iam_member" "proxy_metrics_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.metrics.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.proxy_vm_sa_email}"
}

# ✅ SECURE: Individual IAM members instead of bindings to prevent overwriting existing memberships
# IAM members are additive and safer than bindings which are authoritative

# Logging permissions - individual members for each service account
resource "google_project_iam_member" "runner_cp_logging" {
  count   = !local.using_pre_created_service_accounts && local.runner_sa_email != "" ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${local.runner_sa_email}"
}

resource "google_project_iam_member" "env_vm_logging" {
  count   = !local.using_pre_created_service_accounts && local.environment_vm_sa_email != "" ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${local.environment_vm_sa_email}"
}

resource "google_project_iam_member" "build_cache_logging" {
  count   = !local.using_pre_created_service_accounts && local.build_cache_sa_email != "" ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${local.build_cache_sa_email}"
}

resource "google_project_iam_member" "secret_manager_logging" {
  count   = !local.using_pre_created_service_accounts && local.secret_manager_sa_email != "" ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${local.secret_manager_sa_email}"
}

resource "google_project_iam_member" "pubsub_processor_logging" {
  count   = !local.using_pre_created_service_accounts && local.pubsub_processor_sa_email != "" ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${local.pubsub_processor_sa_email}"
}

# Monitoring permissions - individual members for each service account
resource "google_project_iam_member" "runner_cp_monitoring" {
  count   = !local.using_pre_created_service_accounts && local.runner_sa_email != "" ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${local.runner_sa_email}"
}

resource "google_project_iam_member" "env_vm_monitoring" {
  count   = !local.using_pre_created_service_accounts && local.environment_vm_sa_email != "" ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${local.environment_vm_sa_email}"
}

resource "google_project_iam_member" "pubsub_processor_monitoring" {
  count   = !local.using_pre_created_service_accounts && local.pubsub_processor_sa_email != "" ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${local.pubsub_processor_sa_email}"
}

# Service account for proxy VMs
resource "google_service_account" "proxy_vm" {
  count = var.pre_created_service_accounts.proxy_vm == "" ? 1 : 0

  account_id   = "${var.runner_name}-proxy-vm"
  display_name = "Ona Proxy VM Service"
  description  = "Service account for Ona proxy VM instances"
  project      = var.project_id
}

# Custom role with minimal permissions for proxy VM
resource "google_project_iam_custom_role" "proxy_vm" {
  count = var.pre_created_service_accounts.proxy_vm == "" ? 1 : 0

  role_id     = "${replace(var.runner_name, "-", "_")}_proxy_vm"
  title       = "Ona Proxy VM Minimal"
  description = "Minimal permissions for Ona proxy VM instances"
  project     = var.project_id

  permissions = [
    # Basic instance metadata reading (for self-introspection)
    "compute.instances.get",
    "compute.instances.list",

    # Network information reading (for proxy functionality)
    "compute.networks.get",
    "compute.subnetworks.get",

    # Zone/region information (for location awareness)
    "compute.zones.get",
    "compute.regions.get",

    # Project information (for service discovery)
    "compute.projects.get",
  ]
}

# IAM permissions for proxy VM service
resource "google_project_iam_member" "proxy_vm_logging" {
  count   = !local.using_pre_created_service_accounts && local.proxy_vm_sa_email != "" ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${local.proxy_vm_sa_email}"
}

resource "google_project_iam_member" "proxy_vm_monitoring" {
  count   = !local.using_pre_created_service_accounts && local.proxy_vm_sa_email != "" ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${local.proxy_vm_sa_email}"
}

# ✅ SECURE: Custom role with minimal permissions instead of compute.instanceAdmin.v1
resource "google_project_iam_member" "proxy_vm_compute" {
  count   = !local.using_pre_created_service_accounts && local.proxy_vm_sa_email != "" ? 1 : 0
  project = var.project_id
  role    = var.pre_created_service_accounts.proxy_vm == "" ? google_project_iam_custom_role.proxy_vm[0].id : "projects/${var.project_id}/roles/${replace(var.runner_name, "-", "_")}_proxy_vm"
  member  = "serviceAccount:${local.proxy_vm_sa_email}"

  depends_on = [
    google_project_iam_custom_role.proxy_vm,
    google_service_account.proxy_vm
  ]
}

resource "google_project_iam_member" "proxy_vm_artifact_registry" {
  count   = !local.using_pre_created_service_accounts && local.proxy_vm_sa_email != "" ? 1 : 0
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${local.proxy_vm_sa_email}"
}

resource "google_project_iam_member" "proxy_vm_cloud_run" {
  count   = !local.using_pre_created_service_accounts && local.proxy_vm_sa_email != "" ? 1 : 0
  project = var.project_id
  role    = "roles/run.viewer"
  member  = "serviceAccount:${local.proxy_vm_sa_email}"
}

# Certificate Manager viewer role for external LB certificate access
resource "google_project_iam_member" "proxy_vm_certificate_manager" {
  count   = !local.using_pre_created_service_accounts && local.proxy_vm_sa_email != "" && var.loadbalancer_type == "external" ? 1 : 0
  project = var.project_id
  role    = "roles/certificatemanager.viewer"
  member  = "serviceAccount:${local.proxy_vm_sa_email}"
}

# Secret Manager access for internal LB certificate secret
resource "google_secret_manager_secret_iam_member" "proxy_vm_certificate_secret_access" {
  count     = var.certificate_secret_id != "" ? 1 : 0
  project   = var.project_id
  secret_id = split("/", var.certificate_secret_id)[3]
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.proxy_vm_sa_email}"
}

# GCS access for runner assets bucket (proxy VMs)
resource "google_storage_bucket_iam_member" "proxy_vm_runner_assets_access" {
  bucket = google_storage_bucket.runner_assets.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${local.proxy_vm_sa_email}"
}

# ================================
# AUDIT LOGGING CONFIGURATION
# ================================

# Enable comprehensive audit logging for Secret Manager operations
resource "google_project_iam_audit_config" "secret_manager_audit" {
  project = var.project_id
  service = "secretmanager.googleapis.com"

  audit_log_config {
    log_type         = "DATA_READ" # This logs secret access
    exempted_members = []          # No exemptions - log everything
  }

  audit_log_config {
    log_type = "DATA_WRITE" # This logs secret creation/updates
  }

  audit_log_config {
    log_type = "ADMIN_READ" # This logs metadata access
  }
}

# Enable comprehensive audit logging for Compute Engine operations
resource "google_project_iam_audit_config" "compute_audit" {
  project = var.project_id
  service = "compute.googleapis.com"

  audit_log_config {
    log_type = "ADMIN_READ"
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

# Enable comprehensive audit logging for IAM operations
resource "google_project_iam_audit_config" "iam_audit" {
  project = var.project_id
  service = "iam.googleapis.com"

  audit_log_config {
    log_type = "ADMIN_READ"
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

# Enable audit logging for Storage operations
resource "google_project_iam_audit_config" "storage_audit" {
  project = var.project_id
  service = "storage.googleapis.com"

  audit_log_config {
    log_type         = "DATA_READ"
    exempted_members = []
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

# GCS access for runner assets bucket (environment VMs)
resource "google_storage_bucket_iam_member" "env_vm_runner_assets_access" {
  bucket = google_storage_bucket.runner_assets.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${local.environment_vm_sa_email}"
}

# ================================
# KMS ACCESS FOR CMEK ENCRYPTION
# ================================

# KMS access for all service accounts when CMEK is enabled
resource "google_kms_crypto_key_iam_member" "runner_kms_access" {
  count = (var.create_cmek || var.kms_key_name != null) && local.runner_sa_email != "" ? 1 : 0

  crypto_key_id = local.kms_key_name
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${local.runner_sa_email}"
}

resource "google_kms_crypto_key_iam_member" "environment_vm_kms_access" {
  count = (var.create_cmek || var.kms_key_name != null) && local.environment_vm_sa_email != "" ? 1 : 0

  crypto_key_id = local.kms_key_name
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${local.environment_vm_sa_email}"
}

resource "google_kms_crypto_key_iam_member" "build_cache_kms_access" {
  count = (var.create_cmek || var.kms_key_name != null) && local.build_cache_sa_email != "" ? 1 : 0

  crypto_key_id = local.kms_key_name
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${local.build_cache_sa_email}"
}

resource "google_kms_crypto_key_iam_member" "secret_manager_kms_access" {
  count = (var.create_cmek || var.kms_key_name != null) && local.secret_manager_sa_email != "" ? 1 : 0

  crypto_key_id = local.kms_key_name
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${local.secret_manager_sa_email}"
}

resource "google_kms_crypto_key_iam_member" "pubsub_processor_kms_access" {
  count = (var.create_cmek || var.kms_key_name != null) && local.pubsub_processor_sa_email != "" ? 1 : 0

  crypto_key_id = local.kms_key_name
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${local.pubsub_processor_sa_email}"
}

resource "google_kms_crypto_key_iam_member" "proxy_vm_kms_access" {
  count = (var.create_cmek || var.kms_key_name != null) && local.proxy_vm_sa_email != "" ? 1 : 0

  crypto_key_id = local.kms_key_name
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${local.proxy_vm_sa_email}"
}
