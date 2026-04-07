# Enable required Google Cloud services first
module "services" {
  source = "./modules/services"

  project_id = var.project_id
}

# Networking
module "networking" {
  source = "./modules/networking"

  project_id             = var.project_id
  name_prefix            = var.runner_name
  region                 = var.region
  vpc_name               = "${var.runner_name}-vpc"
  subnet_cidr            = "10.0.0.0/24"
  create_private_network = var.loadbalancer_type == "internal"

  depends_on = [module.services]
}

module "dns" {
  source = "./modules/dns"

  project_id   = var.project_id
  name_prefix  = var.runner_name
  proxy_domain = var.runner_domain

  create_dns_auth   = var.certificate_id == "" && var.certificate_secret_id == ""
  loadbalancer_type = var.loadbalancer_type
}

# Self-signed certificate for internal LB when no cert is provided and certbot is not enabled.
# Internal LB needs a cert in Secret Manager; external LB uses Certificate Manager.
module "self_signed_cert" {
  source = "./modules/self-signed-cert"

  create      = var.loadbalancer_type == "internal" && var.certificate_secret_id == "" && !var.enable_certbot
  project_id  = var.project_id
  name_prefix = var.runner_name
  domain      = var.runner_domain

  depends_on = [module.services]
}

# Automatic certificate management via Let's Encrypt.
# Issues a wildcard cert using DNS-01 challenges against Cloud DNS,
# stores it in Secret Manager, and schedules daily renewal.
module "certbot" {
  source = "./modules/certbot"
  count  = var.enable_certbot ? 1 : 0

  project_id          = var.project_id
  region              = var.region
  runner_name         = var.runner_name
  runner_id           = var.runner_id
  runner_domain       = var.runner_domain
  acme_email          = var.certbot_email
  dns_zone_name       = module.dns.zone_name
  run_initial_certbot = var.run_initial_certbot

  depends_on = [module.services, module.dns]
}

locals {
  vpc_name           = module.networking.vpc_name
  runner_subnet_name = module.networking.runner_subnet_name

  # Certbot-created secret takes priority, then user-provided, then self-signed.
  resolved_certificate_secret_id = var.enable_certbot ? module.certbot[0].certificate_secret_id : (
    var.certificate_secret_id != "" ? var.certificate_secret_id : module.self_signed_cert.certificate_secret_id
  )

  # Size profiles: "small" optimizes for cost (test/dev), "regular" for production.
  size_profiles = {
    small = {
      runner_vm_config = {
        machine_type = "n4-standard-2"
        update_policy_config = {
          minimal_action     = "REPLACE"
          surge_percentage   = 25
          max_unavailable    = 0
          replacement_method = "SUBSTITUTE"
        }
      }
      proxy_vm_config = {
        machine_type                    = "n4-standard-2"
        min_instances                   = 1
        max_instances                   = 2
        connection_draining_timeout_sec = 300
        update_policy_config = {
          minimal_action     = "REPLACE"
          surge_percentage   = 50
          max_unavailable    = 0
          replacement_method = "SUBSTITUTE"
        }
      }
      redis_config = {
        shard_count          = 3
        replica_count        = 0
        node_type            = "REDIS_STANDARD_SMALL"
        psc_connection_limit = 10
        custom_configs       = {}
      }
    }
    regular = {
      runner_vm_config = {
        machine_type = "c4-standard-4"
        update_policy_config = {
          minimal_action     = "REPLACE"
          surge_percentage   = 25
          max_unavailable    = 0
          replacement_method = "SUBSTITUTE"
        }
      }
      proxy_vm_config = {
        machine_type                    = "c4-standard-2"
        min_instances                   = 2
        max_instances                   = 5
        connection_draining_timeout_sec = 300
        update_policy_config = {
          minimal_action     = "REPLACE"
          surge_percentage   = 50
          max_unavailable    = 0
          replacement_method = "SUBSTITUTE"
        }
      }
      redis_config = {
        shard_count          = 3
        replica_count        = 1
        node_type            = "REDIS_STANDARD_SMALL"
        psc_connection_limit = 10
        custom_configs       = {}
      }
    }
  }

  selected_profile = local.size_profiles[var.runner_size]
}

module "runner" {
  source = "../.."

  project_id         = var.project_id
  runner_name        = var.runner_name
  region             = var.region
  vpc_name           = local.vpc_name
  runner_subnet_name = local.runner_subnet_name

  development_version = var.development_version
  runner_id           = var.runner_id
  runner_token        = var.runner_token
  zones               = var.zones
  runner_domain       = var.runner_domain
  proxy_config        = var.proxy_config
  ca_certificate      = var.ca_certificate

  ssh_port     = var.ssh_port
  api_endpoint = var.api_endpoint

  certificate_id          = var.certificate_id != "" ? var.certificate_id : module.dns.certificate_id
  certificate_secret_id   = local.resolved_certificate_secret_id
  certificate_secret_read = !var.enable_certbot

  loadbalancer_type = var.loadbalancer_type

  runner_vm_config = local.selected_profile.runner_vm_config
  proxy_vm_config  = local.selected_profile.proxy_vm_config
  redis_config     = local.selected_profile.redis_config

  routable_subnet_name = local.runner_subnet_name
  create_cmek          = var.create_cmek
  kms_key_name         = var.kms_key_name

  depends_on = [module.networking, module.dns, module.self_signed_cert, module.certbot]
}

# DNS wildcard record
resource "google_dns_record_set" "wildcard" {
  count        = var.certificate_id == "" && var.certificate_secret_id == "" ? 1 : 0
  name         = "*.${module.dns.zone_dns_name}"
  type         = "A"
  ttl          = 300
  managed_zone = module.dns.zone_name
  project      = var.project_id

  rrdatas = [module.runner.proxy_ip]
}

# DNS root record
resource "google_dns_record_set" "root" {
  count        = var.certificate_id == "" && var.certificate_secret_id == "" ? 1 : 0
  name         = module.dns.zone_dns_name
  type         = "A"
  ttl          = 300
  managed_zone = module.dns.zone_name
  project      = var.project_id

  rrdatas = [module.runner.proxy_ip]
}
