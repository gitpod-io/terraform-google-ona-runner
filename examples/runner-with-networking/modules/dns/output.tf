output "zone_name" {
  value = var.create_dns_auth ? google_dns_managed_zone.proxy[0].name : ""
}

output "zone_dns_name" {
  value = var.create_dns_auth ? google_dns_managed_zone.proxy[0].dns_name : ""
}

output "ns_records" {
  value = var.create_dns_auth ? google_dns_managed_zone.proxy[0].name_servers : []
}

output "certificate_id" {
  value = local.create_cert ? google_certificate_manager_certificate.proxy_cert[0].id : ""
}
