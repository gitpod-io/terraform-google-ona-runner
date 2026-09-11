output "vpc_name" {
  description = "Name of the restricted runner VPC."
  value       = google_compute_network.runner.name
}

output "runner_subnet_name" {
  description = "Name of the runner and environment subnet."
  value       = google_compute_subnetwork.runner.name
}

output "google_apis_psc_ip" {
  description = "Internal IP address of the Google APIs PSC endpoint."
  value       = google_compute_global_address.google_apis.address
}

output "network_firewall_policy_name" {
  description = "Name of the default-deny Cloud NGFW policy."
  value       = google_compute_network_firewall_policy.egress.name
}

output "dns_query_logging_policy_name" {
  description = "Name of the Cloud DNS policy that records resolver queries."
  value       = google_dns_policy.query_logging.name
}

output "security_log_bucket" {
  description = "Resource name of the dedicated restricted-runner security log bucket."
  value       = google_logging_project_bucket_config.security_archive.id
}

output "url_filtering_security_profile_group" {
  description = "Cloud NGFW Enterprise security profile group used for environment HTTPS traffic."
  value       = "https://networksecurity.googleapis.com/v1/${google_network_security_security_profile_group.url_filtering.id}"
}

output "firewall_allowed_domains" {
  description = "Public HTTPS domains allowed by Cloud NGFW."
  value       = local.firewall_allowed_domains
}

output "internal_runner_ips" {
  description = "Static internal IP addresses assigned to the runner instances."
  value       = module.runner.internal_runner_ips
}

output "internal_runner_hostname" {
  description = "Private DNS hostname shared by the runner instances."
  value       = module.runner.internal_runner_hostname
}
