# Proxy VM Instance Group Module
# Deploy proxy service in a container on Compute Engine VM instances


# Cloud-init configuration for proxy VMs
data "cloudinit_config" "proxy" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/files/proxy-cloud-init.tftpl", {
      RUNNER_ID             = var.runner_id
      PROJECT_ID            = var.project_id
      REGION                = var.region
      PROXY_DOMAIN          = var.runner_domain
      PROXY_IMAGE_URL       = local.proxy_image
      PROMETHEUS_IMAGE      = local.prometheus_image
      LOADBALANCER_TYPE     = var.loadbalancer_type
      CERTIFICATE_ID        = var.certificate_id
      CERTIFICATE_SECRET_ID = var.certificate_secret_id
      METRICS_SECRET_ID     = "${var.runner_id}-metrics"
      API_ENDPOINT          = var.api_endpoint
      # Proxy configuration
      HTTP_PROXY  = local.http_proxy
      HTTPS_PROXY = local.https_proxy
      NO_PROXY    = local.no_proxy
      ALL_PROXY   = local.all_proxy
      # CA certificate configuration
      CA_ENABLED     = local.ca_enabled
      CA_BUCKET_NAME = local.ca_bucket_name
      CA_OBJECT_NAME = local.ca_object_name
      # Docker config configuration
      DOCKER_CONFIG_ENABLED     = local.docker_config_enabled
      DOCKER_CONFIG_BUCKET_NAME = local.docker_config_bucket_name
      DOCKER_CONFIG_OBJECT_NAME = local.docker_config_object_name
      # Insecure registries configuration
      INSECURE_REGISTRIES_ENABLED = local.insecure_registries_enabled
      INSECURE_REGISTRIES_JSON    = local.insecure_registries_json
    })
  }
}

# Create instance template for proxy VMs
resource "google_compute_instance_template" "proxy" {
  name_prefix  = "${var.runner_name}-proxy-"
  project      = var.project_id
  machine_type = var.proxy_vm_config.machine_type
  region       = var.region

  tags = ["gitpod-proxy", "gitpod-type-proxy"]

  labels = local.proxy_labels

  disk {
    source_image = "cos-cloud/cos-stable"
    auto_delete  = true
    boot         = true
    disk_size_gb = 10
    disk_type    = "hyperdisk-balanced"

    # Optional CMEK encryption for boot disk
    dynamic "disk_encryption_key" {
      for_each = local.kms_key_name != null ? [1] : []
      content {
        kms_key_self_link = local.kms_key_name
      }
    }
  }

  network_interface {
    network            = "projects/${local.vpc_project_id}/global/networks/${var.vpc_name}"
    subnetwork         = var.runner_subnet_name
    subnetwork_project = local.vpc_project_id
    nic_type           = "GVNIC"
  }

  service_account {
    email = local.proxy_vm_sa_email
    scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/compute.readonly",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  shielded_instance_config {
    enable_secure_boot = true
  }

  # Container-Optimized OS metadata for running the proxy container
  metadata = {
    google-logging-enabled       = "true"
    google-monitoring-enabled    = "true"
    google-logging-use-fluentbit = "true"
    serial-port-logging-enable   = "true"

    # Cloud-init configuration for proxy setup
    user-data = data.cloudinit_config.proxy.rendered

    "cos-metrics-enabled" = "true"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Create managed instance group
resource "google_compute_region_instance_group_manager" "proxy" {
  name                      = "${var.runner_name}-proxy-group"
  region                    = var.region
  project                   = var.project_id
  base_instance_name        = "${var.runner_name}-proxy"
  distribution_policy_zones = var.zones

  version {
    instance_template = google_compute_instance_template.proxy.id
  }

  named_port {
    name = "https"
    port = 8443
  }

  named_port {
    name = "http"
    port = 8080
  }

  named_port {
    name = "health"
    port = 5000
  }

  update_policy {
    # Use rolling update for zero-downtime deployments
    type                         = "PROACTIVE"
    instance_redistribution_type = "PROACTIVE"

    # Configurable actions for different update scenarios
    minimal_action                 = var.proxy_vm_config.update_policy_config.minimal_action
    most_disruptive_allowed_action = "REPLACE"

    # Rolling update configuration for zero downtime
    # Critical for proxy: configurable surge capacity (default 50% for high availability)
    max_surge_fixed       = max(length(var.zones), 2)
    max_unavailable_fixed = var.proxy_vm_config.update_policy_config.max_unavailable == 0 ? 0 : max(length(var.zones), var.proxy_vm_config.update_policy_config.max_unavailable)

    # Configurable replacement method for optimization
    replacement_method = var.proxy_vm_config.update_policy_config.replacement_method
  }

  wait_for_instances = true

  lifecycle {
    create_before_destroy = true
  }
}

# Create autoscaler for the instance group
resource "google_compute_region_autoscaler" "proxy" {
  name    = "${var.runner_name}-proxy-autoscaler"
  region  = var.region
  target  = google_compute_region_instance_group_manager.proxy.id
  project = var.project_id

  autoscaling_policy {
    min_replicas    = var.proxy_vm_config.min_instances
    max_replicas    = var.proxy_vm_config.max_instances
    cooldown_period = 60

    cpu_utilization {
      target = 0.7
    }

    load_balancing_utilization {
      target = 0.8
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}
