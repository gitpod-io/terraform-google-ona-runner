locals {
  name_prefix       = trimsuffix(substr(lower(var.runner_name), 0, 24), "-")
  psc_endpoint_name = trimsuffix(substr("${local.name_prefix}-apis", 0, 20), "-")

  firewall_allowed_domains = sort(tolist(toset([
    for domain in var.firewall_allowed_domains : lower(domain)
  ])))

  google_api_dns_domains = toset([
    "gcr.io",
    "googleapis.com",
    "pkg.dev",
  ])

  extended_audit_services = toset([
    "artifactregistry.googleapis.com",
    "cloudkms.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ])

  security_log_filter = trimspace(<<-EOT
    log_id("cloudaudit.googleapis.com/activity") OR
    log_id("cloudaudit.googleapis.com/data_access") OR
    log_id("cloudaudit.googleapis.com/policy") OR
    log_id("cloudaudit.googleapis.com/system_event") OR
    log_id("compute.googleapis.com/firewall") OR
    log_id("compute.googleapis.com/nat_flows") OR
    log_id("compute.googleapis.com/vpc_flows") OR
    log_id("dns.googleapis.com/dns_queries") OR
    logName:"networksecurity.googleapis.com"
  EOT
  )

  common_labels = merge(var.labels, {
    "ona-component" = "runner-networking"
  })
}
