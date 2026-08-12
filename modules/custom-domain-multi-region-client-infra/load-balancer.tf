resource "google_compute_backend_service" "relay" {
  project                = var.project_id
  name                   = "${var.service_name}-backend"
  protocol               = "HTTP"
  load_balancing_scheme  = "EXTERNAL_MANAGED"
  timeout_sec            = 300
  custom_request_headers = ["X-Gitpod-GCP-ID: ${var.project_id}"]

  dynamic "backend" {
    for_each = google_compute_region_network_endpoint_group.psc

    content {
      group = backend.value.id
    }
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

resource "google_compute_url_map" "relay" {
  project         = var.project_id
  name            = "${var.service_name}-url-map"
  default_service = google_compute_backend_service.relay.id
}

resource "google_compute_target_https_proxy" "relay" {
  project                          = var.project_id
  name                             = "${var.service_name}-https-proxy"
  url_map                          = google_compute_url_map.relay.id
  certificate_manager_certificates = [var.certificate_manager_cert_id]
}

resource "google_compute_global_address" "relay" {
  project = var.project_id
  name    = "${var.service_name}-lb-ip"
}

resource "google_compute_global_forwarding_rule" "relay" {
  project               = var.project_id
  name                  = "${var.service_name}-https"
  ip_address            = google_compute_global_address.relay.id
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  network_tier          = "PREMIUM"
  port_range            = "443"
  target                = google_compute_target_https_proxy.relay.id
}
