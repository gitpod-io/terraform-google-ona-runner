resource "google_compute_network_firewall_policy" "egress" {
  project     = var.project_id
  name        = "${local.name_prefix}-egress"
  description = "Default-deny egress policy for the restricted Ona runner VPC."

  depends_on = [google_project_service.required]
}

resource "google_compute_network_firewall_policy_association" "egress" {
  project           = var.project_id
  name              = "${local.name_prefix}-egress"
  attachment_target = google_compute_network.runner.id
  firewall_policy   = google_compute_network_firewall_policy.egress.name
}

resource "google_compute_network_firewall_policy_rule" "internal" {
  project         = var.project_id
  firewall_policy = google_compute_network_firewall_policy.egress.name
  priority        = 100
  direction       = "EGRESS"
  action          = "goto_next"
  rule_name       = "allow-internal-vpc"
  description     = "Allow internal VPC traffic to continue through the runner module's VPC firewall rules."

  match {
    dest_ip_ranges = [var.subnet_cidr]

    layer4_configs {
      ip_protocol = "all"
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "google_apis_psc" {
  project         = var.project_id
  firewall_policy = google_compute_network_firewall_policy.egress.name
  priority        = 200
  direction       = "EGRESS"
  action          = "goto_next"
  rule_name       = "allow-google-apis-psc"
  description     = "Allow HTTPS to the Google APIs Private Service Connect endpoint."

  match {
    dest_ip_ranges = ["${var.psc_google_apis_ip}/32"]

    layer4_configs {
      ip_protocol = "tcp"
      ports       = ["443"]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "allowed_domains" {
  project         = var.project_id
  firewall_policy = google_compute_network_firewall_policy.egress.name
  priority        = 300
  direction       = "EGRESS"
  action          = "goto_next"
  rule_name       = "allow-https-domains"
  description     = "Allow HTTPS to explicitly approved public domains."

  match {
    dest_fqdns = local.firewall_allowed_domains

    layer4_configs {
      ip_protocol = "tcp"
      ports       = ["443"]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "allowed_ip_ranges" {
  count = length(var.firewall_allowed_ip_ranges) > 0 ? 1 : 0

  project         = var.project_id
  firewall_policy = google_compute_network_firewall_policy.egress.name
  priority        = 400
  direction       = "EGRESS"
  action          = "goto_next"
  rule_name       = "allow-https-ip-ranges"
  description     = "Allow HTTPS to explicitly approved public IPv4 ranges."

  match {
    dest_ip_ranges = sort(tolist(var.firewall_allowed_ip_ranges))

    layer4_configs {
      ip_protocol = "tcp"
      ports       = ["443"]
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "deny_all" {
  project         = var.project_id
  firewall_policy = google_compute_network_firewall_policy.egress.name
  priority        = 65000
  direction       = "EGRESS"
  action          = "deny"
  rule_name       = "deny-all-egress"
  description     = "Deny all egress not matched by an explicit allow rule."
  enable_logging  = true

  match {
    dest_ip_ranges = ["0.0.0.0/0"]

    layer4_configs {
      ip_protocol = "all"
    }
  }
}
