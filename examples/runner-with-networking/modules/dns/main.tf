# DNS managed zone
resource "google_dns_managed_zone" "proxy" {
  count       = var.create_dns_auth ? 1 : 0
  name        = "${var.name_prefix}-proxy-zone"
  dns_name    = "${var.proxy_domain}."
  project     = var.project_id
  description = "DNS zone for Ona proxy domain"

  labels = var.labels
}

locals {
  # Certificate Manager resources are only needed for external LB
  create_cert = var.create_dns_auth && var.loadbalancer_type == "external"
}

# DNS authorization for wildcard certificate (external LB only)
resource "google_certificate_manager_dns_authorization" "proxy_dns_auth" {
  count   = local.create_cert ? 1 : 0
  name    = "${var.name_prefix}-proxy-dns-auth"
  domain  = var.proxy_domain
  project = var.project_id
}

# DNS record for certificate authorization (external LB only)
resource "google_dns_record_set" "cert_validation" {
  count        = local.create_cert ? 1 : 0
  name         = google_certificate_manager_dns_authorization.proxy_dns_auth[0].dns_resource_record[0].name
  managed_zone = google_dns_managed_zone.proxy[0].name
  type         = google_certificate_manager_dns_authorization.proxy_dns_auth[0].dns_resource_record[0].type
  ttl          = 300
  rrdatas      = [google_certificate_manager_dns_authorization.proxy_dns_auth[0].dns_resource_record[0].data]
  project      = var.project_id
}

# Certificate Manager certificate with wildcard support (external LB only)
resource "google_certificate_manager_certificate" "proxy_cert" {
  count       = local.create_cert ? 1 : 0
  name        = "${var.name_prefix}-proxy-cert"
  description = "The wildcard cert for ${var.proxy_domain}"
  project     = var.project_id

  managed {
    domains            = [var.proxy_domain, "*.${var.proxy_domain}"]
    dns_authorizations = [google_certificate_manager_dns_authorization.proxy_dns_auth[0].id]
  }

  labels = {
    "terraform" = "true"
    "component" = "proxy"
  }

  lifecycle {
    create_before_destroy = true
  }
}
