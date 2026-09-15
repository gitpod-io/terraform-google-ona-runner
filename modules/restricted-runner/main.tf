module "runner" {
  source = "../.."

  project_id         = var.project_id
  runner_id          = var.runner_id
  runner_token       = var.runner_token
  runner_name        = var.runner_name
  region             = var.region
  zones              = var.zones
  vpc_name           = var.vpc_name
  vpc_project_id     = var.vpc_project_id
  runner_subnet_name = var.runner_subnet_name
  api_endpoint       = var.api_endpoint
  labels             = var.labels
  restrict_ingress   = true

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
}
