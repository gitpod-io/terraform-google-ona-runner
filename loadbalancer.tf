# External loadbalancer resources 

locals {
  # Validate that routable_subnet_name is provided when loadbalancer_type is internal
  validate_routable_subnet = var.loadbalancer_type == "internal" && var.routable_subnet_name == "" ? tobool("routable_subnet_name must be provided when loadbalancer_type is 'internal'") : true
}

# Health check for HTTP backend service
resource "google_compute_health_check" "proxy_http" {
  count   = var.loadbalancer_type == "external" ? 1 : 0
  name    = "${var.runner_name}-proxy-http-health"
  project = var.project_id

  timeout_sec         = 10
  check_interval_sec  = 10
  healthy_threshold   = 2
  unhealthy_threshold = 3

  # Enable detailed logging for debugging health check failures
  log_config {
    enable = true
  }

  https_health_check {
    port         = 5000
    request_path = "/_health"
  }
}

# SSL health check for port 8443 (global - for external LB)
resource "google_compute_health_check" "proxy_ssl" {
  count   = var.loadbalancer_type == "external" ? 1 : 0
  name    = "${var.runner_name}-proxy-ssl-health"
  project = var.project_id

  timeout_sec         = 10
  check_interval_sec  = 10
  healthy_threshold   = 2
  unhealthy_threshold = 3

  # Enable detailed logging for debugging health check failures
  log_config {
    enable = true
  }

  ssl_health_check {
    port = 8443
  }
}

# Backend service for SSL load balancer using Instance Group (external only)
resource "google_compute_backend_service" "proxy" {
  count                 = var.loadbalancer_type == "external" ? 1 : 0
  name                  = "${var.runner_name}-proxy-backend"
  project               = var.project_id
  load_balancing_scheme = "EXTERNAL"
  protocol              = "SSL"
  timeout_sec           = 86400
  port_name             = "https"

  backend {
    group           = google_compute_region_instance_group_manager.proxy.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }

  health_checks = [google_compute_health_check.proxy_ssl[0].id]

  # Enable connection draining with configurable timeout
  connection_draining_timeout_sec = var.proxy_vm_config.connection_draining_timeout_sec

  log_config {
    enable      = true
    sample_rate = 1.0
  }

  depends_on = [
    google_compute_health_check.proxy_ssl[0],
    google_compute_region_instance_group_manager.proxy,
    google_compute_region_autoscaler.proxy
  ]
}

# Backend service for HTTP traffic (TCP protocol) - external only
resource "google_compute_backend_service" "proxy_http" {
  count                 = var.loadbalancer_type == "external" ? 1 : 0
  name                  = "${var.runner_name}-proxy-http-backend"
  project               = var.project_id
  load_balancing_scheme = "EXTERNAL"
  protocol              = "TCP"
  timeout_sec           = 86400
  port_name             = "http"

  backend {
    group           = google_compute_region_instance_group_manager.proxy.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }

  health_checks = [google_compute_health_check.proxy_http[0].id]

  # Enable connection draining with configurable timeout
  connection_draining_timeout_sec = var.proxy_vm_config.connection_draining_timeout_sec

  log_config {
    enable      = true
    sample_rate = 1.0
  }

  depends_on = [
    google_compute_health_check.proxy_http[0],
    google_compute_region_instance_group_manager.proxy,
    google_compute_region_autoscaler.proxy
  ]
}

# Certificate map for using existing Certificate Manager certificate (external LB only)
resource "google_certificate_manager_certificate_map" "proxy_cert_map" {
  count       = var.loadbalancer_type == "external" ? 1 : 0
  name        = "${var.runner_name}-proxy-cert-map"
  description = "${var.runner_domain} certificate map"
  project     = var.project_id

  labels = {
    "terraform" = "true"
    "component" = "proxy"
  }
}

# Certificate map entry for root domain (external LB only)
resource "google_certificate_manager_certificate_map_entry" "proxy_cert_map_entry" {
  count        = var.loadbalancer_type == "external" ? 1 : 0
  name         = "${var.runner_name}-proxy-cert-map-entry"
  map          = google_certificate_manager_certificate_map.proxy_cert_map[0].name
  certificates = [var.certificate_id]
  matcher      = "PRIMARY"
  project      = var.project_id
}

# Certificate map entry for wildcard domain (external LB only)
resource "google_certificate_manager_certificate_map_entry" "proxy_wildcard_cert_map_entry" {
  count        = var.loadbalancer_type == "external" ? 1 : 0
  name         = "${var.runner_name}-proxy-wildcard-cert-map-entry"
  map          = google_certificate_manager_certificate_map.proxy_cert_map[0].name
  certificates = [var.certificate_id]
  hostname     = "*.${var.runner_domain}"
  project      = var.project_id
}

# SSL target proxy for TLS termination at load balancer (external only)
resource "google_compute_target_ssl_proxy" "proxy" {
  count           = var.loadbalancer_type == "external" ? 1 : 0
  name            = "${var.runner_name}-proxy-ssl"
  project         = var.project_id
  backend_service = google_compute_backend_service.proxy[0].id
  certificate_map = "//certificatemanager.googleapis.com/projects/${var.project_id}/locations/global/certificateMaps/${google_certificate_manager_certificate_map.proxy_cert_map[0].name}"
}

# TCP target proxy for HTTP traffic (port 80) - external only
resource "google_compute_target_tcp_proxy" "proxy_http" {
  count           = var.loadbalancer_type == "external" ? 1 : 0
  name            = "${var.runner_name}-proxy-http-tcp"
  project         = var.project_id
  backend_service = google_compute_backend_service.proxy_http[0].id
}

# Global static IP for external load balancer
resource "google_compute_global_address" "proxy_ip" {
  count   = var.loadbalancer_type == "external" ? 1 : 0
  name    = "${var.runner_name}-proxy-ip"
  project = var.project_id
}

# Global forwarding rule for HTTPS (port 443) - external SSL proxy
resource "google_compute_global_forwarding_rule" "https" {
  count                 = var.loadbalancer_type == "external" ? 1 : 0
  name                  = "${var.runner_name}-proxy-https"
  project               = var.project_id
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "443"
  target                = google_compute_target_ssl_proxy.proxy[0].id
  ip_address            = google_compute_global_address.proxy_ip[0].id
}

# Global forwarding rule for HTTP (port 80) - external TCP
resource "google_compute_global_forwarding_rule" "http" {
  count                 = var.loadbalancer_type == "external" ? 1 : 0
  name                  = "${var.runner_name}-proxy-http"
  project               = var.project_id
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_tcp_proxy.proxy_http[0].id
  ip_address            = google_compute_global_address.proxy_ip[0].id
}

# Internal loadbalancer resources (we only have one backend service for internal LB for port 443 (proxied to 8443 on proxy VMs))

# Regional SSL health check for port 8443 (for internal LB)
resource "google_compute_region_health_check" "proxy_ssl_internal" {
  count   = var.loadbalancer_type == "internal" ? 1 : 0
  name    = "${var.runner_name}-proxy-ssl-internal-health"
  project = var.project_id
  region  = var.region

  timeout_sec         = 10
  check_interval_sec  = 10
  healthy_threshold   = 2
  unhealthy_threshold = 3

  # Enable detailed logging for debugging health check failures
  log_config {
    enable = true
  }

  ssl_health_check {
    port = 8443
  }
}

# Regional backend service for HTTPS traffic (internal TCP proxy mode)
resource "google_compute_region_backend_service" "proxy_internal" {
  count                 = var.loadbalancer_type == "internal" ? 1 : 0
  name                  = "${var.runner_name}-proxy-internal-backend"
  project               = var.project_id
  region                = var.region
  load_balancing_scheme = "INTERNAL_MANAGED"
  protocol              = "TCP"
  timeout_sec           = 86400
  port_name             = "https"

  backend {
    group           = google_compute_region_instance_group_manager.proxy.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }

  health_checks = [google_compute_region_health_check.proxy_ssl_internal[0].id]

  # Enable connection draining with configurable timeout
  connection_draining_timeout_sec = var.proxy_vm_config.connection_draining_timeout_sec

  log_config {
    enable      = true
    sample_rate = 1.0
  }

  depends_on = [
    google_compute_region_health_check.proxy_ssl_internal,
    google_compute_region_instance_group_manager.proxy,
    google_compute_region_autoscaler.proxy
  ]
}

# Regional static IP for internal load balancer HTTPS
resource "google_compute_address" "proxy_internal_ip" {
  count        = var.loadbalancer_type == "internal" ? 1 : 0
  name         = "${var.runner_name}-proxy-internal-ip"
  project      = var.project_id
  region       = var.region
  subnetwork   = "projects/${local.vpc_project_id}/regions/${var.region}/subnetworks/${var.routable_subnet_name}"
  address_type = "INTERNAL"
}

# Regional TCP target proxy for internal load balancer (TCP proxy mode)
resource "google_compute_region_target_tcp_proxy" "proxy_internal" {
  count           = var.loadbalancer_type == "internal" ? 1 : 0
  name            = "${var.runner_name}-proxy-internal-tcp"
  project         = var.project_id
  region          = var.region
  backend_service = google_compute_region_backend_service.proxy_internal[0].id
}

# Regional forwarding rule for HTTPS (port 443) - internal TCP proxy
resource "google_compute_forwarding_rule" "https_internal" {
  count                 = var.loadbalancer_type == "internal" ? 1 : 0
  name                  = "${var.runner_name}-proxy-https-internal"
  project               = var.project_id
  region                = var.region
  ip_protocol           = "TCP"
  load_balancing_scheme = "INTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_region_target_tcp_proxy.proxy_internal[0].id
  ip_address            = google_compute_address.proxy_internal_ip[0].id
  network               = "projects/${local.vpc_project_id}/global/networks/${var.vpc_name}"
  subnetwork            = "projects/${local.vpc_project_id}/regions/${var.region}/subnetworks/${var.routable_subnet_name}"
}
