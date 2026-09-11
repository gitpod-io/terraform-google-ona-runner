resource "google_network_security_security_profile" "url_filtering" {
  count = var.enable_url_filtering ? 1 : 0

  parent      = "projects/${var.project_id}"
  location    = "global"
  name        = "${local.name_prefix}-url-filter"
  description = "Allow only the restricted runner's approved HTTPS domains."
  type        = "URL_FILTERING"
  labels      = local.common_labels

  url_filtering_profile {
    url_filters {
      priority         = 1000
      filtering_action = "ALLOW"
      urls             = local.firewall_allowed_domains
    }
  }

  depends_on = [google_project_service.required]
}

resource "google_network_security_security_profile_group" "url_filtering" {
  count = var.enable_url_filtering ? 1 : 0

  parent                = "projects/${var.project_id}"
  location              = "global"
  name                  = "${local.name_prefix}-url-filter"
  description           = "URL filtering profile group for restricted environment egress."
  url_filtering_profile = google_network_security_security_profile.url_filtering[0].self_link
  labels                = local.common_labels
}

resource "google_network_security_firewall_endpoint" "url_filtering" {
  for_each = var.enable_url_filtering ? toset(var.zones) : toset([])

  parent             = "projects/${var.project_id}"
  location           = each.value
  name               = "${local.name_prefix}-egress"
  billing_project_id = var.project_id
  labels             = local.common_labels

  depends_on = [google_project_service.required]
}

resource "google_network_security_firewall_endpoint_association" "url_filtering" {
  for_each = google_network_security_firewall_endpoint.url_filtering

  parent                = "projects/${var.project_id}"
  location              = each.key
  name                  = "${local.name_prefix}-egress"
  firewall_endpoint     = each.value.self_link
  network               = google_compute_network.runner.self_link
  tls_inspection_policy = var.url_filtering_tls_inspection_policy
  labels                = local.common_labels
}

resource "google_compute_network_firewall_policy_rule" "url_filtering_allowed_ip_ranges" {
  count = var.enable_url_filtering && length(var.firewall_allowed_ip_ranges) > 0 ? 1 : 0

  project                 = var.project_id
  firewall_policy         = google_compute_network_firewall_policy.egress.name
  priority                = 225
  direction               = "EGRESS"
  action                  = "goto_next"
  rule_name               = "allow-environment-https-ip-ranges"
  description             = "Preserve explicit IP allowlist entries before environment HTTPS inspection."
  target_service_accounts = [module.runner.environment_vm_service_account_email]

  match {
    dest_ip_ranges = sort(tolist(var.firewall_allowed_ip_ranges))

    layer4_configs {
      ip_protocol = "tcp"
      ports       = ["443"]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "url_filtering" {
  count = var.enable_url_filtering ? 1 : 0

  project                 = var.project_id
  firewall_policy         = google_compute_network_firewall_policy.egress.name
  priority                = 250
  direction               = "EGRESS"
  action                  = "apply_security_profile_group"
  rule_name               = "inspect-environment-https"
  description             = "Apply SNI and URL filtering to environment HTTPS traffic."
  enable_logging          = true
  security_profile_group  = "https://networksecurity.googleapis.com/v1/${google_network_security_security_profile_group.url_filtering[0].id}"
  target_service_accounts = [module.runner.environment_vm_service_account_email]
  tls_inspect             = var.url_filtering_tls_inspection_policy != null

  match {
    dest_ip_ranges = ["0.0.0.0/0"]

    layer4_configs {
      ip_protocol = "tcp"
      ports       = ["443"]
    }
  }

  depends_on = [google_network_security_firewall_endpoint_association.url_filtering]
}

resource "google_compute_packet_mirroring" "environment" {
  count = var.packet_mirroring_collector_forwarding_rule == null ? 0 : 1

  project     = var.project_id
  region      = var.region
  name        = "${local.name_prefix}-environment"
  description = "Mirror restricted environment VM traffic to the operator-managed collector."

  network {
    url = google_compute_network.runner.self_link
  }

  collector_ilb {
    url = var.packet_mirroring_collector_forwarding_rule
  }

  mirrored_resources {
    tags = ["gitpod-type-environment"]
  }

  filter {
    direction = "BOTH"
  }
}
