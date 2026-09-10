output "proxy_ip" {
  description = "IP address of the runner proxy"
  value       = var.loadbalancer_type == "external" ? google_compute_global_address.proxy_ip[0].address : google_compute_address.proxy_internal_ip[0].address
}

output "load_balancer_backend_services" {
  description = "Name of the proxy VM"
  value       = var.loadbalancer_type == "external" ? google_compute_backend_service.proxy[0].name : google_compute_region_backend_service.proxy_internal[0].name
}

output "load_balancer_ip" {
  description = "IP address of the runner proxy"
  value       = var.loadbalancer_type == "external" ? google_compute_global_address.proxy_ip[0].address : google_compute_address.proxy_internal_ip[0].address
}

output "runner_instance_group_name" {
  description = "Name of the runner VM instance gruop manager"
  value       = google_compute_region_instance_group_manager.runner.name
}

output "proxy_instance_group_name" {
  description = "Name of the proxy VM instance gruop manager"
  value       = google_compute_region_instance_group_manager.proxy.name
}

output "runner_service_account_email" {
  description = "Service account of runner"
  value       = local.runner_sa_email
}

output "proxy_service_account_email" {
  description = "Service account of the proxy VM"
  value       = local.proxy_vm_sa_email
}

output "environment_vm_service_account_email" {
  description = "Service account of environment VM"
  value       = local.environment_vm_sa_email
}

output "auth_proxy_tls_cert" {
  description = "TLS certificate for the auth proxy (for VM trust)"
  value       = tls_self_signed_cert.auth_proxy.cert_pem
  sensitive   = true
}

output "logs_url" {
  description = "Dashboard URL of logs explorer"
  value       = local.logs_url
}

output "internal_runner_ips" {
  description = "Reserved internal runner IPs, not yet attached to VMs. Empty when restrict_ingress is disabled."
  value       = google_compute_address.internal_runner[*].address
}

output "internal_runner_hostname" {
  description = "Private DNS hostname for the reserved runner IPs. Null when restrict_ingress is disabled."
  value       = local.internal_runner_hostname
}

output "internal_runner_tls" {
  description = "Prepared internal HTTPS identity and runner configuration. Activation still requires IP ownership, firewall rules, and compatible runner/environment releases. Contains no private key."
  value = var.restrict_ingress ? {
    certificate_pem = tls_self_signed_cert.internal_runner[0].cert_pem
    environment = {
      INTERNAL_RUNNER_ENDPOINT           = "https://${local.internal_runner_hostname}:8089"
      INTERNAL_RUNNER_LLM_PORT           = "8089"
      INTERNAL_RUNNER_TLS_SECRET         = google_secret_manager_secret.internal_runner_tls["tls"].secret_id
      INTERNAL_RUNNER_TLS_SECRET_VERSION = google_secret_manager_secret_version.internal_runner_tls[0].version
    }
  } : null
}
