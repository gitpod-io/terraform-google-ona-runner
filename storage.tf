# Private Service Connect Connection Policy for Redis Cluster
# Note: The service connection policy must be created in the same project as the network (VPC project)
resource "google_network_connectivity_service_connection_policy" "redis_psc_policy" {
  name     = "${var.runner_name}-redis-psc-policy"
  location = var.region
  project  = local.vpc_project_id # Must be in the VPC/network project for shared VPC

  service_class = "gcp-memorystore-redis"
  description   = "PSC connection policy for Redis Cluster"

  network = "projects/${local.vpc_project_id}/global/networks/${var.vpc_name}"

  psc_config {
    subnetworks = ["projects/${local.vpc_project_id}/regions/${var.region}/subnetworks/${var.runner_subnet_name}"]
    limit       = var.redis_config.psc_connection_limit != null ? var.redis_config.psc_connection_limit : 10
  }

  labels = merge(var.labels, {
    gitpod-component = "redis-psc-policy"
    managed-by       = "terraform"
  })
}

# Store Redis credentials in Secret Manager (always enabled for security)
resource "google_secret_manager_secret" "redis_auth" {
  project   = var.project_id
  secret_id = "${var.runner_name}-redis-auth"

  labels = merge(var.labels, {
    gitpod-component = "redis-auth"
    managed-by       = "terraform"
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

resource "google_secret_manager_secret_version" "redis_auth" {
  secret = google_secret_manager_secret.redis_auth.id

  secret_data = jsonencode({
    # High availability - all cluster node addresses for direct connection
    hosts = [
      for endpoint in google_redis_cluster.cache.discovery_endpoints :
      "${endpoint.address}:${endpoint.port}"
    ]

    # Security configuration
    auth_string = "" # Empty for IAM auth - tokens are generated dynamically
    tls_enabled = google_redis_cluster.cache.transit_encryption_mode == "TRANSIT_ENCRYPTION_MODE_SERVER_AUTHENTICATION"
    server_ca_certs = [
      for cert in google_redis_cluster.cache.managed_server_ca[0].ca_certs[0].certificates : {
        serial_number = ""   # Redis Cluster doesn't provide serial number
        cert          = cert # The actual certificate PEM data
        create_time   = ""   # Redis Cluster doesn't provide create time
        expire_time   = ""   # Redis Cluster doesn't provide expire time
      }
    ]
  })
}

# Metrics configuration secret for Prometheus
resource "google_secret_manager_secret" "metrics" {
  project   = var.project_id
  secret_id = "${var.runner_id}-metrics"

  labels = merge(var.labels, {
    gitpod-component = "metrics"
    managed-by       = "terraform"
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

# Initial empty metrics configuration
resource "google_secret_manager_secret_version" "metrics" {
  secret = google_secret_manager_secret.metrics.id

  secret_data = jsonencode({
    enable_metrics = false
    url            = ""
    user           = ""
    password       = ""
    created_by     = "terraform"
  })

  lifecycle {
    ignore_changes = [secret_data]
  }
}

# Redis Cluster for state management with Private Service Connect
resource "google_redis_cluster" "cache" {
  name          = "${var.runner_name}-redis-cluster"
  project       = var.project_id
  region        = var.region
  shard_count   = var.redis_config.shard_count != null ? var.redis_config.shard_count : 3
  replica_count = var.redis_config.replica_count != null ? var.redis_config.replica_count : 1
  node_type     = var.redis_config.node_type != null ? var.redis_config.node_type : "REDIS_STANDARD_SMALL"
  redis_configs = var.redis_config.custom_configs != null ? var.redis_config.custom_configs : {}

  # Private Service Connect configuration
  psc_configs {
    network = "projects/${local.vpc_project_id}/global/networks/${var.vpc_name}"
  }

  # CMEK encryption (optional)
  kms_key = local.kms_key_name

  # Security settings - always enabled for production
  authorization_mode      = "AUTH_MODE_IAM_AUTH"
  transit_encryption_mode = "TRANSIT_ENCRYPTION_MODE_SERVER_AUTHENTICATION"

  # Allow destruction for development/testing
  deletion_protection_enabled = false

  # Maintenance window - Sunday 3 AM UTC
  maintenance_policy {
    weekly_maintenance_window {
      day = "SUNDAY"
      start_time {
        hours   = 3
        minutes = 0
        seconds = 0
        nanos   = 0
      }
    }
  }

  lifecycle {
    prevent_destroy = false
    # create_before_destroy must NOT be true here: it inverts the destroy
    # ordering, causing terraform to delete the PSC policy before the Redis
    # cluster. The PSC policy deletion then fails with "still has PSC
    # Connections associated with it" because the cluster is still alive.
    ignore_changes = [
      maintenance_policy[0].weekly_maintenance_window[0].start_time
    ]
  }

  depends_on = [google_network_connectivity_service_connection_policy.redis_psc_policy]
}

# GCS bucket for storing runner assets
resource "google_storage_bucket" "runner_assets" {
  name     = "${var.runner_id}-runner-assets"
  project  = var.project_id
  location = var.region

  # Security settings
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # CMEK encryption (optional)
  dynamic "encryption" {
    for_each = local.kms_key_name != null ? [1] : []
    content {
      default_kms_key_name = local.kms_key_name
    }
  }

  labels = merge(var.labels, {
    gitpod-component = "runner-assets"
    managed-by       = "terraform"
  })
}

# GCS bucket for storing agent execution artifacts
resource "google_storage_bucket" "agent_storage" {
  count = var.enable_agents ? 1 : 0

  name     = "${var.runner_id}-agent-storage"
  project  = var.project_id
  location = var.region

  # Security settings
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Lifecycle management
  lifecycle_rule {
    condition {
      age = 365 # Delete agent artifacts after 1 year
    }
    action {
      type = "Delete"
    }
  }

  # CMEK encryption (optional)
  dynamic "encryption" {
    for_each = local.kms_key_name != null ? [1] : []
    content {
      default_kms_key_name = local.kms_key_name
    }
  }

  labels = merge(var.labels, {
    gitpod-component = "agent-storage"
    managed-by       = "terraform"
  })
}

# Read certificate from Secret Manager if provided and readable.
# When certificate_secret_read is false (e.g. certbot-managed certs), the secret
# may not have a version yet, so we skip the read. The proxy VM's cert-refresh
# timer will fetch the certificate once it becomes available.
data "google_secret_manager_secret_version" "certificate" {
  count = var.certificate_secret_id != "" && var.certificate_secret_read ? 1 : 0

  secret = var.certificate_secret_id
}

# Create combined trust bundle certificate (CA cert + Secret Manager cert)
locals {
  # Extract certificate from Secret Manager if available and readable
  secret_certificate = var.certificate_secret_id != "" && var.certificate_secret_read ? jsondecode(data.google_secret_manager_secret_version.certificate[0].secret_data)["certificate"] : ""

  # Get CA certificate content if available
  ca_certificate_content = var.ca_certificate != null ? (var.ca_certificate.file_path != "" ? file(var.ca_certificate.file_path) : var.ca_certificate.content) : ""

  # Combine certificates with proper formatting (ensure each cert ends with newline)
  combined_certificate = join("\n", compact([
    local.ca_certificate_content != "" ? trimspace(local.ca_certificate_content) : null,
    local.secret_certificate != "" ? trimspace(local.secret_certificate) : null
  ]))

  # Determine if we need a combined certificate file
  has_certificates = var.ca_certificate != null || (var.certificate_secret_id != "" && var.certificate_secret_read)
}

# Upload combined trust bundle certificate to GCS bucket.
# create_before_destroy ensures the new object is written before the old
# one is removed, preventing a gap if terraform apply is interrupted.
resource "google_storage_bucket_object" "trust_bundle" {
  count = local.has_certificates ? 1 : 0

  name   = "trust-bundle.pem"
  bucket = google_storage_bucket.runner_assets.name

  # Use combined certificate content
  content = local.combined_certificate

  content_type = "application/x-pem-file"

  # Metadata for tracking
  metadata = {
    uploaded_by     = "terraform"
    runner_id       = var.runner_id
    source          = "combined-trust-bundle"
    has_ca_cert     = var.ca_certificate != null ? "true" : "false"
    has_secret_cert = var.certificate_secret_id != "" && var.certificate_secret_read ? "true" : "false"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Upload Docker config.json to GCS bucket if provided
resource "google_storage_bucket_object" "docker_config" {
  count = local.docker_config_enabled ? 1 : 0

  name   = "docker-config.json"
  bucket = google_storage_bucket.runner_assets.name

  # Use Docker config.json content directly
  content = var.custom_images.docker_config_json

  content_type = "application/json"

  # Metadata for tracking
  metadata = {
    uploaded_by = "terraform"
    runner_id   = var.runner_id
  }
}
