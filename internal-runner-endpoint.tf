locals {
  internal_runner_hostname = var.restrict_ingress ? trimsuffix(google_dns_record_set.internal_runner[0].name, ".") : null
}

resource "google_compute_address" "internal_runner" {
  count = var.restrict_ingress ? 2 : 0

  project      = var.project_id
  name         = "${var.runner_name}-internal-${count.index}"
  region       = var.region
  address_type = "INTERNAL"
  subnetwork   = "projects/${local.vpc_project_id}/regions/${var.region}/subnetworks/${var.runner_subnet_name}"
  labels       = local.runner_labels
}

resource "google_dns_managed_zone" "internal_runner" {
  count = var.restrict_ingress ? 1 : 0

  project     = var.project_id
  name        = "${var.runner_name}-internal"
  dns_name    = "ona-${var.runner_id}.internal."
  description = "Private DNS for the Ona runner"
  visibility  = "private"
  labels      = local.runner_labels

  private_visibility_config {
    networks {
      network_url = "https://www.googleapis.com/compute/v1/projects/${local.vpc_project_id}/global/networks/${var.vpc_name}"
    }
  }
}

resource "google_dns_record_set" "internal_runner" {
  count = var.restrict_ingress ? 1 : 0

  project      = var.project_id
  managed_zone = google_dns_managed_zone.internal_runner[0].name
  name         = "runner.${google_dns_managed_zone.internal_runner[0].dns_name}"
  type         = "A"
  ttl          = 10
  rrdatas      = google_compute_address.internal_runner[*].address
}

resource "google_secret_manager_secret" "internal_runner_tls" {
  for_each = var.restrict_ingress ? toset(["key", "tls"]) : toset([])

  project   = var.project_id
  secret_id = "${var.runner_id}-internal-llm-${each.key}"
  labels    = merge(local.runner_labels, { gitpod-component = "internal-llm-tls" })

  replication {
    dynamic "user_managed" {
      for_each = local.kms_key_name != null ? [1] : []
      content {
        replicas {
          location = var.region
          customer_managed_encryption {
            kms_key_name = local.kms_key_name
          }
        }
      }
    }

    dynamic "auto" {
      for_each = local.kms_key_name == null ? [1] : []
      content {}
    }
  }

  depends_on = [google_kms_crypto_key_iam_member.google_secretmanager]
}

ephemeral "tls_private_key" "internal_runner_tls" {
  count = var.restrict_ingress ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "google_secret_manager_secret_version" "internal_runner_key" {
  count = var.restrict_ingress ? 1 : 0

  secret                 = google_secret_manager_secret.internal_runner_tls["key"].id
  secret_data_wo         = ephemeral.tls_private_key.internal_runner_tls[0].private_key_pem
  secret_data_wo_version = var.internal_runner_endpoint_version
  deletion_policy        = "ABANDON"

  lifecycle {
    create_before_destroy = true
  }
}

# Reuse the persisted key if an apply fails between certificate issuance and
# the runner secret write. A fresh ephemeral candidate would not match that certificate.
ephemeral "google_secret_manager_secret_version" "internal_runner_key" {
  count = var.restrict_ingress ? 1 : 0

  secret  = google_secret_manager_secret.internal_runner_tls["key"].id
  version = google_secret_manager_secret_version.internal_runner_key[0].version
}

resource "tls_self_signed_cert" "internal_runner" {
  count = var.restrict_ingress ? 1 : 0

  private_key_pem_wo         = ephemeral.google_secret_manager_secret_version.internal_runner_key[0].secret_data
  private_key_pem_wo_version = tonumber(google_secret_manager_secret_version.internal_runner_key[0].version)

  subject {
    common_name  = local.internal_runner_hostname
    organization = "Ona internal runner"
  }

  dns_names             = [local.internal_runner_hostname]
  validity_period_hours = 87600
  is_ca_certificate     = true
  allowed_uses          = ["digital_signature", "key_encipherment", "server_auth", "cert_signing"]

  lifecycle {
    create_before_destroy = true
    # A replacement secret can restart numbering at version 1 with a different key.
    replace_triggered_by = [google_secret_manager_secret_version.internal_runner_key[0]]
  }
}

resource "google_secret_manager_secret_version" "internal_runner_tls" {
  count = var.restrict_ingress ? 1 : 0

  secret = google_secret_manager_secret.internal_runner_tls["tls"].id
  secret_data_wo = jsonencode({
    certificate = tls_self_signed_cert.internal_runner[0].cert_pem
    privateKey  = ephemeral.google_secret_manager_secret_version.internal_runner_key[0].secret_data
  })
  secret_data_wo_version = var.internal_runner_endpoint_version
  deletion_policy        = "ABANDON"

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [tls_self_signed_cert.internal_runner[0]]
  }
}

resource "google_secret_manager_secret_iam_member" "internal_runner_tls" {
  count = var.restrict_ingress && local.manage_service_account_iam_policies ? 1 : 0

  project   = var.project_id
  secret_id = google_secret_manager_secret.internal_runner_tls["tls"].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.runner_sa_email}"
}
