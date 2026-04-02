terraform {
  required_version = ">= 1.3"
  required_providers {
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

resource "tls_private_key" "cert" {
  count     = var.create ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "cert" {
  count           = var.create ? 1 : 0
  private_key_pem = tls_private_key.cert[0].private_key_pem

  subject {
    common_name  = var.domain
    organization = "Gitpod"
  }

  dns_names = [
    var.domain,
    "*.${var.domain}",
  ]

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# Store cert in Secret Manager in the format the proxy VM expects
resource "google_secret_manager_secret" "cert" {
  count     = var.create ? 1 : 0
  project   = var.project_id
  secret_id = "${var.name_prefix}-self-signed-cert"

  labels = merge(var.labels, {
    gitpod-component = "self-signed-cert"
    managed-by       = "terraform"
  })

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "cert" {
  count  = var.create ? 1 : 0
  secret = google_secret_manager_secret.cert[0].id

  secret_data = jsonencode({
    certificate = tls_self_signed_cert.cert[0].cert_pem
    privateKey  = tls_private_key.cert[0].private_key_pem
  })
}
