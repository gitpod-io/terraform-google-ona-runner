resource "google_secret_manager_secret" "identity" {
  for_each = toset(["key", "tls"])

  project   = var.project_id
  secret_id = "${var.secret_prefix}-${each.key}"
  labels    = var.labels

  replication {
    dynamic "user_managed" {
      for_each = var.kms_key_name != null ? [1] : []
      content {
        replicas {
          location = var.region
          customer_managed_encryption {
            kms_key_name = var.kms_key_name
          }
        }
      }
    }

    dynamic "auto" {
      for_each = var.kms_key_name == null ? [1] : []
      content {}
    }
  }
}

ephemeral "tls_private_key" "candidate" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "google_secret_manager_secret_version" "key" {
  secret                 = google_secret_manager_secret.identity["key"].id
  secret_data_wo         = ephemeral.tls_private_key.candidate.private_key_pem
  secret_data_wo_version = var.generation
  deletion_policy        = "ABANDON"

  lifecycle {
    create_before_destroy = true
  }
}

# Reuse the persisted key if an apply fails between certificate issuance and
# the runner secret write. A fresh ephemeral candidate would not match that certificate.
ephemeral "google_secret_manager_secret_version" "key" {
  secret  = google_secret_manager_secret.identity["key"].id
  version = google_secret_manager_secret_version.key.version
}

resource "tls_self_signed_cert" "runner" {
  private_key_pem_wo         = ephemeral.google_secret_manager_secret_version.key.secret_data
  private_key_pem_wo_version = tonumber(google_secret_manager_secret_version.key.version)

  subject {
    common_name  = var.hostname
    organization = "Ona internal runner"
  }

  dns_names             = [var.hostname]
  validity_period_hours = 87600
  is_ca_certificate     = true
  allowed_uses          = ["digital_signature", "key_encipherment", "server_auth", "cert_signing"]

  lifecycle {
    create_before_destroy = true
    # A replacement secret can restart numbering at version 1 with a different key.
    replace_triggered_by = [google_secret_manager_secret_version.key]
  }
}

resource "google_secret_manager_secret_version" "pair" {
  secret = google_secret_manager_secret.identity["tls"].id
  secret_data_wo = jsonencode({
    certificate = tls_self_signed_cert.runner.cert_pem
    privateKey  = ephemeral.google_secret_manager_secret_version.key.secret_data
  })
  secret_data_wo_version = var.generation
  deletion_policy        = "ABANDON"

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [tls_self_signed_cert.runner]
  }
}
