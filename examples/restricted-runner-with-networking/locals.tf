locals {
  name_prefix       = trimsuffix(substr(lower(var.runner_name), 0, 24), "-")
  psc_endpoint_name = trimsuffix(substr("${local.name_prefix}-apis", 0, 20), "-")

  firewall_allowed_domains = sort(tolist(toset([
    for domain in var.firewall_allowed_domains : lower(domain)
  ])))

  proxy_endpoint_parts = var.proxy_config == null ? [] : [
    for proxy_url in distinct(compact([
      var.proxy_config.http_proxy,
      var.proxy_config.https_proxy,
      var.proxy_config.all_proxy,
      ])) : regex(
      "^[A-Za-z][A-Za-z0-9+.-]*://([^@/]+@)?([^:/?#]+):([0-9]{1,5})$",
      proxy_url,
    )
  ]
  proxy_endpoint_groups = {
    for endpoint in local.proxy_endpoint_parts :
    "${lower(endpoint[1])}:${endpoint[2]}" => {
      host = lower(endpoint[1])
      port = endpoint[2]
    }...
  }
  proxy_endpoints = {
    for key, endpoints in local.proxy_endpoint_groups :
    key => endpoints[0]
  }
  proxy_endpoint_keys = sort(keys(local.proxy_endpoints))
  proxy_domain_endpoints = {
    for key, endpoint in local.proxy_endpoints : key => endpoint
    if !can(cidrnetmask("${endpoint.host}/32"))
  }
  proxy_ip_endpoints = {
    for key, endpoint in local.proxy_endpoints : key => endpoint
    if can(cidrnetmask("${endpoint.host}/32"))
  }

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
