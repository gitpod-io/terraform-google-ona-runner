# Runner VM Instance Group Module
# Deploy runner service in a container on Compute Engine VM instances

locals {
  auth_proxy_url = "https://4430s--${var.runner_id}.${var.runner_domain}/initial-spec"

  proxy_enabled = var.proxy_config != null
  ca_enabled    = var.ca_certificate != null

  http_proxy  = local.proxy_enabled ? var.proxy_config.http_proxy : ""
  https_proxy = local.proxy_enabled ? var.proxy_config.https_proxy : ""
  all_proxy   = local.proxy_enabled ? var.proxy_config.all_proxy : ""
  # we add some default values to the no_proxy variable along with the customer provided values
  no_proxy = local.proxy_enabled ? "${var.proxy_config.no_proxy},localhost,127.0.0.1,googleapis.com,metadata.google.internal,${var.runner_domain}" : ""

  # Trust bundle certificate GCS bucket and object info
  ca_bucket_name = local.has_certificates ? google_storage_bucket.runner_assets.name : ""
  ca_object_name = local.has_certificates ? google_storage_bucket_object.trust_bundle[0].name : ""

  # Agent storage bucket (only created when agents are enabled)
  agent_bucket_name = var.enable_agents ? google_storage_bucket.agent_storage[0].name : ""
}

# ================================
# TLS CERTIFICATE FOR AUTH PROXY
# ================================


# Time-based rotation trigger - rotates certificates every 30 days
resource "time_rotating" "auth_proxy_cert_rotation" {
  rotation_days = 30
}

# Create a self-signed certificate for auth proxy internal use
resource "tls_private_key" "auth_proxy" {
  algorithm = "RSA"
  rsa_bits  = 2048

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [time_rotating.auth_proxy_cert_rotation]
  }
}

resource "tls_self_signed_cert" "auth_proxy" {
  private_key_pem = tls_private_key.auth_proxy.private_key_pem

  subject {
    common_name  = "${var.runner_name}-auth-proxy.internal"
    organization = "Gitpod"
  }

  validity_period_hours = 8760 # 1 year

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [time_rotating.auth_proxy_cert_rotation]
  }

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]

  dns_names = [
    "${var.runner_name}-auth-proxy.internal",
    "auth-proxy.internal",
    "localhost"
  ]

  ip_addresses = [
    "127.0.0.1"
  ]
}


# Artifact Registry for container images
resource "google_artifact_registry_repository" "runner" {
  location      = var.region
  repository_id = "gitpod-cache-${var.runner_id}"
  description   = "Container images for Ona runner"
  format        = "DOCKER"
  project       = var.project_id
  kms_key_name  = local.kms_key_name

  labels = local.runner_labels

  docker_config {
    immutable_tags = true
  }

  cleanup_policies {
    id     = "expire-old-images"
    action = "DELETE"
    condition {
      tag_state  = "ANY"
      older_than = "2592000s" # 30 days
    }
  }
}
# Cloud-init configuration for runner VMs
data "cloudinit_config" "runner" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/files/runner-cloud-init.tftpl", {
      RUNNER_ID                            = var.runner_id
      PROJECT_ID                           = var.project_id
      REGION                               = var.region
      ZONES                                = join(",", var.zones)
      VPC_NAME                             = var.vpc_name
      VPC_PROJECT_ID                       = local.vpc_project_id
      SUBNET_NAME                          = var.runner_subnet_name
      RUNNER_TOKEN_SECRET                  = google_secret_manager_secret.runner_token.secret_id
      REDIS_CREDENTIALS_SECRET             = google_secret_manager_secret.redis_auth.secret_id
      SERVICE_ACCOUNT_EMAIL                = local.runner_sa_email
      ENVIRONMENT_VM_SERVICE_ACCOUNT_EMAIL = local.environment_vm_sa_email
      ARTIFACT_REGISTRY_HOST               = "${var.region}-docker.pkg.dev"
      API_ENDPOINT                         = var.api_endpoint
      BUILD_CACHE_BUCKET                   = google_storage_bucket.build_cache.name
      PROXY_DOMAIN                         = var.runner_domain
      SSH_PORT                             = var.ssh_port
      INSTANCE_GROUP_NAME                  = "${var.runner_name}-group"
      RUNNER_IMAGE_URL                     = var.development_version != "" ? local.runner_dev_image : local.runner_image
      DEVELOPMENT_VERSION                  = var.development_version
      PUBSUB_SUBSCRIPTION_ID               = google_pubsub_subscription.compute_events.name
      AUTH_PROXY_URL                       = local.auth_proxy_url
      AUTH_PROXY_TLS_CERT                  = tls_self_signed_cert.auth_proxy.cert_pem
      AUTH_PROXY_TLS_KEY                   = tls_private_key.auth_proxy.private_key_pem
      RUNNER_LOGS_URL                      = local.logs_url
      PROMETHEUS_IMAGE                     = local.prometheus_image
      NODE_EXPORTER_IMAGE                  = local.node_exporter_image
      LOADBALANCER_TYPE                    = var.loadbalancer_type
      CERTIFICATE_ID                       = var.certificate_id
      CERTIFICATE_SECRET_ID                = var.certificate_secret_id
      METRICS_SECRET_ID                    = "${var.runner_id}-metrics"
      ENABLE_AGENTS                        = var.enable_agents
      AGENT_BUCKET_NAME                    = local.agent_bucket_name
      RUNNER_ASSETS_BUCKET_NAME            = google_storage_bucket.runner_assets.name
      HONEYCOMB_API_KEY                    = var.honeycomb_api_key
      MIG_WARM_POOL_ENABLED                = true
      # Proxy configuration
      HTTP_PROXY  = local.http_proxy
      HTTPS_PROXY = local.https_proxy
      NO_PROXY    = local.no_proxy
      ALL_PROXY   = local.all_proxy
      # CA certificate configuration
      CA_ENABLED       = local.ca_enabled
      HAS_TRUST_BUNDLE = local.has_certificates
      CA_BUCKET_NAME   = local.ca_bucket_name
      CA_OBJECT_NAME   = local.ca_object_name
      # Docker config configuration
      DOCKER_CONFIG_ENABLED     = local.docker_config_enabled
      DOCKER_CONFIG_BUCKET_NAME = local.docker_config_bucket_name
      DOCKER_CONFIG_OBJECT_NAME = local.docker_config_object_name
      # Insecure registries configuration
      INSECURE_REGISTRIES_ENABLED = local.insecure_registries_enabled
      INSECURE_REGISTRIES_JSON    = local.insecure_registries_json
      # CMEK configuration
      KMS_KEY_NAME = local.kms_key_name
      # Custom image registry configuration
      RUNNER_USES_CUSTOM_IMAGE = local.runner_uses_custom_image
      CUSTOM_RUNNER_REGISTRY   = local.custom_runner_registry
      # Environment VM labels configuration
      ENVIRONMENT_VM_LABELS = join(",", [for k, v in var.labels : "${k}=${v}"])
      # Module version reported to the management plane
      TERRAFORM_MODULE_VERSION = local.module_version
    })
  }
}

# Create instance template for runner VMs
resource "google_compute_instance_template" "runner" {
  name_prefix  = "${var.runner_name}-runner-"
  project      = var.project_id
  machine_type = var.runner_vm_config.machine_type
  region       = var.region

  tags = ["gitpod-runner", "gitpod-type-runner", "allow-health-check", "lb-health-check", "gitpod-runner-${var.runner_id}"]

  labels = local.runner_labels

  disk {
    source_image = "cos-cloud/cos-stable"
    auto_delete  = true
    boot         = true
    disk_size_gb = 20
    disk_type    = "hyperdisk-balanced"

    # Optional CMEK encryption for boot disk
    dynamic "disk_encryption_key" {
      for_each = local.kms_key_name != null ? [1] : []
      content {
        kms_key_self_link = local.kms_key_name
      }
    }
  }

  shielded_instance_config {
    enable_secure_boot = true
  }


  network_interface {
    network            = "projects/${local.vpc_project_id}/global/networks/${var.vpc_name}"
    subnetwork         = var.runner_subnet_name
    subnetwork_project = local.vpc_project_id
    nic_type           = "GVNIC"
  }

  service_account {
    email = local.runner_sa_email
    scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/devstorage.read_write",
      "https://www.googleapis.com/auth/pubsub",
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  # Container-Optimized OS metadata for running the runner container
  metadata = {
    google-logging-enabled       = "true"
    google-monitoring-enabled    = "true"
    google-logging-use-fluentbit = "true"
    serial-port-logging-enable   = "true"

    # Cloud-init configuration for Prometheus setup
    user-data = data.cloudinit_config.runner.rendered

    "cos-metrics-enabled" = "true"
  }


  lifecycle {
    create_before_destroy = true
  }
}

# Create managed instance group
resource "google_compute_region_instance_group_manager" "runner" {
  # enables features like min_ready_sec
  provider = google-beta

  name                      = "${var.runner_name}-group"
  region                    = var.region
  project                   = var.project_id
  base_instance_name        = var.runner_name
  distribution_policy_zones = var.zones

  instance_lifecycle_policy {
    default_action_on_failure = "REPAIR"
    force_update_on_repair    = "NO"
  }

  version {
    instance_template = google_compute_instance_template.runner.id
  }

  named_port {
    name = "http"
    port = 8080
  }

  named_port {
    name = "health"
    port = 9091
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.runner.id
    initial_delay_sec = 120 # Reduced from 180 for faster deletion while allowing startup
  }

  update_policy {
    # Use rolling update for zero-downtime deployments
    type                         = "PROACTIVE"
    instance_redistribution_type = "PROACTIVE"

    # Configurable actions for different update scenarios
    minimal_action                 = var.runner_vm_config.update_policy_config.minimal_action
    most_disruptive_allowed_action = "REPLACE"

    # Rolling update configuration optimized for self-updating runner
    # Surge-first strategy: create new instances before destroying old ones
    # This ensures the updater instance survives until the very end
    max_surge_fixed       = max(length(var.zones), 2)
    max_unavailable_fixed = var.runner_vm_config.update_policy_config.max_unavailable == 0 ? 0 : max(length(var.zones), var.runner_vm_config.update_policy_config.max_unavailable)

    # Use SUBSTITUTE method to create new instances before destroying old ones
    replacement_method = "SUBSTITUTE"

    # Slower, safer updates to ensure stability - aligned with health check timing
    min_ready_sec = 120 # 2 minutes to allow for container startup and initial health checks
  }

  wait_for_instances = true

  # Ensure Redis cache is ready before creating runner instances
  depends_on = [google_redis_cluster.cache]

  lifecycle {
    create_before_destroy = true
  }
}

# Create autoscaler for the instance group
resource "google_compute_region_autoscaler" "runner" {
  name    = "${var.runner_name}-autoscaler"
  region  = var.region
  target  = google_compute_region_instance_group_manager.runner.id
  project = var.project_id

  autoscaling_policy {
    min_replicas    = 1 # Always maintain at least 1 runner instance
    max_replicas    = 2 # Allow up to 2 instances for rollouts, scale down to min after
    cooldown_period = 60

    cpu_utilization {
      target = 0.7
    }
  }
}

# Health check for runner service
resource "google_compute_health_check" "runner" {
  name    = "${var.runner_name}-health"
  project = var.project_id

  timeout_sec         = 10 # Increased timeout for slow container responses and network issues
  check_interval_sec  = 20 # Less frequent checks to reduce load during startup
  healthy_threshold   = 2  # Still require 2 consecutive successes
  unhealthy_threshold = 6  # More tolerance for temporary failures during startup

  # Enable detailed logging for debugging health check failures
  log_config {
    enable = true
  }

  http_health_check {
    port         = 9091
    request_path = "/_health"
  }

  lifecycle {
    create_before_destroy = true
  }
}


# Resource tagging for lifecycle management
resource "google_compute_project_metadata" "runner_metadata" {
  project = var.project_id

  metadata = {
    "enable-oslogin"   = "TRUE"
    "gitpod-runner-id" = var.runner_id
  }
}
