# Local for load balancing scheme
locals {
  load_balancing_scheme = var.load_balancer_type == "external" ? "EXTERNAL_MANAGED" : "INTERNAL_MANAGED"
  is_internal           = var.load_balancer_type == "internal"
}

# Regional Backend Service
resource "google_compute_region_backend_service" "lb_backend" {
  name                  = "${local.service_name}-backend"
  region                = var.region
  protocol              = "HTTP"
  load_balancing_scheme = local.load_balancing_scheme
  timeout_sec           = 30
  port_name             = "http"

  backend {
    group           = google_compute_region_network_endpoint_group.psc_neg.id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# Regional URL Map with custom headers
resource "google_compute_region_url_map" "lb" {
  name   = "${local.service_name}-url-map"
  region = var.region

  # Default path matcher with header injection
  default_service = google_compute_region_backend_service.lb_backend.id

  host_rule {
    hosts        = ["*"]
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = google_compute_region_backend_service.lb_backend.id

    route_rules {
      priority = 1
      match_rules {
        prefix_match = "/"
      }
      header_action {
        request_headers_to_add {
          header_name  = "X-Gitpod-GCP-ID"
          header_value = var.project_id
          replace      = true
        }
      }
      route_action {
        weighted_backend_services {
          backend_service = google_compute_region_backend_service.lb_backend.id
          weight          = 100
        }
      }
    }
  }
}

# Regional Target HTTPS Proxy with Certificate Manager
resource "google_compute_region_target_https_proxy" "lb" {
  name                             = "${local.service_name}-https-proxy"
  region                           = var.region
  url_map                          = google_compute_region_url_map.lb.id
  certificate_manager_certificates = [var.certificate_manager_cert_id]
}

# Reserve IP address for load balancer
resource "google_compute_address" "lb_ip" {
  name         = "${local.service_name}-lb-ip"
  address_type = local.is_internal ? "INTERNAL" : "EXTERNAL"
  subnetwork   = local.is_internal ? data.google_compute_subnetwork.subnet.id : null
  region       = var.region
}

# Regional Forwarding Rule (HTTPS)
resource "google_compute_forwarding_rule" "lb_https" {
  name                  = "${local.service_name}-https"
  region                = var.region
  ip_address            = google_compute_address.lb_ip.id
  ip_protocol           = "TCP"
  load_balancing_scheme = local.load_balancing_scheme
  port_range            = "443"
  network               = local.is_internal ? data.google_compute_network.vpc.id : null
  subnetwork            = local.is_internal ? data.google_compute_subnetwork.subnet.id : null
  target                = google_compute_region_target_https_proxy.lb.id
}
