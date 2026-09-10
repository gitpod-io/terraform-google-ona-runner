module "internal_runner_tls" {
  count  = var.restrict_ingress ? 1 : 0
  source = "./modules/internal-runner-tls"

  project_id    = var.project_id
  region        = var.region
  secret_prefix = "${var.runner_id}-internal-llm"
  hostname      = trimsuffix(google_dns_record_set.internal_runner[0].name, ".")
  generation    = var.internal_runner_tls_generation
  kms_key_name  = local.kms_key_name
  labels        = merge(local.runner_labels, { gitpod-component = "internal-llm-tls" })

  depends_on = [google_kms_crypto_key_iam_member.google_secretmanager]
}

resource "google_secret_manager_secret_iam_member" "internal_runner_tls" {
  count = var.restrict_ingress && local.manage_service_account_iam_policies ? 1 : 0

  project   = var.project_id
  secret_id = module.internal_runner_tls[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.runner_sa_email}"
}
