# Customer-Managed Encryption Keys (CMEK) for organizational policy compliance
# This file optionally creates KMS resources and grants permissions when create_cmek = true



# Create KMS keyring if CMEK creation is enabled
resource "google_kms_key_ring" "gitpod" {
  count    = var.create_cmek ? 1 : 0
  name     = "${var.runner_name}-keyring"
  location = var.region
  project  = var.project_id
}

# Create KMS key if CMEK creation is enabled
resource "google_kms_crypto_key" "gitpod" {
  count           = var.create_cmek ? 1 : 0
  name            = "${var.runner_name}-key"
  key_ring        = google_kms_key_ring.gitpod[0].id
  purpose         = "ENCRYPT_DECRYPT"
  rotation_period = "7776000s" # 90 days

  labels = merge(var.labels, {
    gitpod-component = "cmek"
    managed-by       = "terraform"
  })
}
