# DNS Configuration - MANUAL SETUP REQUIRED
output "dns_setup_instructions" {
  description = "DNS setup instructions for domain configuration"
  value = var.certificate_id == "" && var.certificate_secret_id == "" ? format(
    "\n    ⚠️  MANUAL DNS SETUP REQUIRED ⚠️\n    \n    To complete the setup, you must configure your domain's DNS:\n    \n    1. Go to your domain registrar's DNS management panel\n    2. Update the nameservers for your domain to:\n       %s\n    \n    3. Wait for DNS propagation (can take up to 48 hours)\n    4. Verify with: dig NS %s\n    \n    Domain: %s\n    Load Balancer IP: %s\n    ",
    join("\n       ", module.dns.ns_records),
    module.dns.zone_dns_name,
    module.dns.zone_dns_name,
    module.runner.load_balancer_ip
  ) : "DNS management is disabled - using provided certificate"
}

output "dns_ns_records" {
  description = "NS records for the DNS zone - ADD THESE TO YOUR DOMAIN REGISTRAR"
  value       = module.dns.ns_records
}

output "dns_zone_name" {
  description = "DNS zone name"
  value       = module.dns.zone_name
}

output "load_balancer_ip" {
  description = "Load balancer IP address"
  value       = module.runner.load_balancer_ip
}

output "vpc_name" {
  description = "Name of the VPC"
  value       = local.vpc_name
}

output "runner_subnet_name" {
  description = "Name of the runner subnet"
  value       = local.runner_subnet_name
}
