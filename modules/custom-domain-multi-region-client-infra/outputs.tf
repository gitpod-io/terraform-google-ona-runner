output "load_balancer_ip" {
  description = "Global external IP address of the HTTPS load balancer"
  value       = google_compute_global_address.relay.address
}

output "domain_name" {
  description = "Configured custom domain name"
  value       = var.domain_name
}

output "ssl_certificate_used" {
  description = "Certificate Manager certificate resource ID"
  value       = var.certificate_manager_cert_id
}

output "psc_network_endpoint_groups" {
  description = "PSC network endpoint group resource IDs keyed by region"
  value = {
    for region, neg in google_compute_region_network_endpoint_group.psc : region => neg.id
  }
}
