output "load_balancer_ip" {
  description = "IP address of the HTTPS load balancer"
  value       = google_compute_address.lb_ip.address
}

output "load_balancer_type" {
  description = "Type of load balancer deployed (internal or external)"
  value       = var.load_balancer_type
}

output "psc_endpoint_ip" {
  description = "Internal IP address of the PSC endpoint"
  value       = google_compute_address.psc_ip.address
}

output "domain_name" {
  description = "Configured domain name"
  value       = var.domain_name
}

output "ssl_certificate_used" {
  description = "Certificate Manager certificate ID"
  value       = var.certificate_manager_cert_id
}

output "connection_instructions" {
  description = "Instructions for connecting to the Ona instance"
  value       = <<-EOT
    
    ========================================
    CUSTOM DOMAIN CLIENT INFRASTRUCTURE
    ========================================
    
    Domain:           ${var.domain_name}
    Load Balancer IP: ${google_compute_address.lb_ip.address}
    Load Balancer:    ${var.load_balancer_type == "external" ? "External (public)" : "Internal (private)"}
    PSC Endpoint IP:  ${google_compute_address.psc_ip.address}
    Project ID:       ${var.project_id}
    
    HTTPS is enabled with the provided SSL certificate.
    
    ========================================
    SECURITY: AUTOMATIC PROJECT IDENTIFICATION
    ========================================
    
    The load balancer automatically injects the project ID header:
    
      X-Gitpod-GCP-ID: ${var.project_id}
    
    The relay validates this against actual PSC connections.
    This prevents spoofing attacks.
    
    No application changes required - the header is added automatically!
    
    ========================================
    NEXT STEPS
    ========================================
    
    ${var.load_balancer_type == "external" ? "1. Configure public DNS to point ${var.domain_name} to ${google_compute_address.lb_ip.address}" : "1. Configure internal DNS to point ${var.domain_name} to ${google_compute_address.lb_ip.address}"}
    
    2. Test HTTPS connectivity${var.load_balancer_type == "internal" ? " from within your VPC" : ""}:
       curl -v https://${var.domain_name}/
    
    4. Verify PSC connection status:
       gcloud compute forwarding-rules describe ${local.service_name}-psc --region=${var.region}
    
    5. Check backend health:
       gcloud compute backend-services get-health ${local.service_name}-backend --region=${var.region}
    
    ========================================
  EOT
}

output "psc_connection_status" {
  description = "PSC connection status"
  value       = google_compute_forwarding_rule.psc_endpoint.psc_connection_status
}
