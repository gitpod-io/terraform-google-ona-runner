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

  common_labels = merge(var.labels, {
    "ona-component" = "runner-networking"
  })
}
