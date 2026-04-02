output "certificate_secret_id" {
  description = "Full resource ID of the Secret Manager secret containing the certificate"
  # Use the local secret name (derived from inputs) rather than the resource attribute
  # so this value is known at plan time and can be used in count expressions.
  value = "projects/${var.project_id}/secrets/${local.secret_name}"
}
