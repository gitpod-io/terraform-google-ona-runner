output "certificate_pem" {
  description = "Public certificate to include in environment trust bundles."
  value       = tls_self_signed_cert.runner.cert_pem
}

output "secret_id" {
  description = "Runner certificate/key secret resource ID."
  value       = google_secret_manager_secret.identity["tls"].id
}

output "secret_name" {
  description = "Runner certificate/key secret name within the project."
  value       = google_secret_manager_secret.identity["tls"].secret_id
}

output "secret_version" {
  description = "Exact version containing the certificate/key pair."
  value       = google_secret_manager_secret_version.pair.version
}
