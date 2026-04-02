output "certificate_secret_id" {
  description = "Secret Manager secret ID containing the self-signed certificate"
  # Construct from inputs so the value is known at plan time (avoids
  # "count depends on resource attributes" errors in downstream modules).
  value = var.create ? "projects/${var.project_id}/secrets/${var.name_prefix}-self-signed-cert" : ""
}
