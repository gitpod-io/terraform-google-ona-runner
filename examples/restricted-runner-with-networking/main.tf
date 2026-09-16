module "runner" {
  source = "../../modules/restricted-runner"

  project_id         = var.project_id
  runner_id          = var.runner_id
  runner_token       = var.runner_token
  runner_name        = var.runner_name
  region             = var.region
  zones              = var.zones
  vpc_name           = google_compute_network.runner.name
  runner_subnet_name = google_compute_subnetwork.runner.name
  api_endpoint       = var.api_endpoint
  labels             = var.labels

  development_version                = var.development_version
  ssh_port                           = var.ssh_port
  service_ports                      = var.service_ports
  proxy_config                       = var.proxy_config
  ca_certificate                     = var.ca_certificate
  auth_proxy_cert_rotation_triggers  = var.auth_proxy_cert_rotation_triggers
  create_cmek                        = var.create_cmek
  kms_key_name                       = var.kms_key_name
  pre_created_service_accounts       = var.pre_created_service_accounts
  custom_images                      = var.custom_images
  enable_agents                      = var.enable_agents
  enable_cross_zone_restart          = var.enable_cross_zone_restart
  use_authoritative_project_metadata = var.use_authoritative_project_metadata
  internal_runner_endpoint_version   = var.internal_runner_endpoint_version

  depends_on = [
    google_compute_subnetwork.runner,
    google_compute_network_firewall_policy_association.egress,
    google_compute_global_forwarding_rule.google_apis,
    google_dns_record_set.google_apis,
    google_dns_record_set.google_apis_wildcard,
    google_dns_policy.query_logging,
    google_logging_project_sink.security_archive,
    google_project_iam_audit_config.extended,
    google_project_service.required,
  ]
}
