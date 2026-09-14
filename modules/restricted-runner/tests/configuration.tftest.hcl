# Ephemeral resource schemas require real providers, even with resource overrides.
# Data reads are overridden below; this plan test uses no cloud credentials.
provider "google" {
  project      = "runner-project"
  access_token = "unused-plan-test-token"
}

provider "google-beta" {
  project      = "runner-project"
  access_token = "unused-plan-test-token"
}

mock_provider "null" {}
mock_provider "random" {}
mock_provider "time" {}
provider "tls" {}

override_data {
  target = module.runner.data.google_project.current
  values = {
    number = "123456789012"
  }
}

override_data {
  target = module.runner.data.google_compute_subnetwork.runner_subnet
  values = {
    ip_cidr_range = "10.0.0.0/24"
  }
}

override_resource {
  target          = module.runner.google_compute_address.internal_runner[0]
  override_during = plan
  values = {
    address = "10.0.0.10"
    id      = "projects/runner-project/regions/us-central1/addresses/test-runner-internal-0"
  }
}

override_resource {
  target          = module.runner.google_compute_address.internal_runner[1]
  override_during = plan
  values = {
    address = "10.0.0.11"
    id      = "projects/runner-project/regions/us-central1/addresses/test-runner-internal-1"
  }
}

override_resource {
  target          = module.runner.tls_self_signed_cert.internal_runner[0]
  override_during = plan
  values = {
    cert_pem = "internal-runner-certificate"
  }
}

override_resource {
  target          = module.runner.google_secret_manager_secret.internal_runner_tls["tls"]
  override_during = plan
  values = {
    id = "projects/runner-project/secrets/00000000-0000-4000-8000-000000000001-internal-llm-tls"
  }
}

override_resource {
  target          = module.runner.google_secret_manager_secret_version.internal_runner_tls[0]
  override_during = plan
  values = {
    version = "7"
  }
}

variables {
  project_id         = "runner-project"
  runner_id          = "00000000-0000-4000-8000-000000000001"
  runner_token       = "test-token"
  runner_name        = "test-runner"
  region             = "us-central1"
  zones              = ["us-central1-a", "us-central1-b"]
  vpc_name           = "runner-vpc"
  runner_subnet_name = "runner-subnet"

  development_version = "test-development-version"
  ssh_port            = 30222
  service_ports = {
    runner_http_port   = 18080
    runner_health_port = 19091
    proxy_https_port   = 18443
    proxy_http_port    = 15000
  }
  proxy_config = {
    http_proxy  = "http://proxy.example.com:3128"
    https_proxy = "http://proxy.example.com:3128"
    no_proxy    = ".example.internal"
    all_proxy   = "socks5://proxy.example.com:1080"
  }
  ca_certificate = {
    content = "test-custom-ca-certificate"
  }
  auth_proxy_cert_rotation_triggers = {
    incident = "2026-09-14"
  }
  kms_key_name = "projects/runner-project/locations/us-central1/keyRings/ona/cryptoKeys/runner"
  pre_created_service_accounts = {
    runner              = "runner@runner-project.iam.gserviceaccount.com"
    environment_vm      = "environment@runner-project.iam.gserviceaccount.com"
    attach_iam_policies = false
  }
  custom_images = {
    runner_image        = "registry.example.com/ona/runner:test"
    prometheus_image    = "registry.example.com/ona/prometheus:test"
    node_exporter_image = "registry.example.com/ona/node-exporter:test"
    docker_config_json  = "{\"auths\":{}}"
    insecure            = true
  }
  enable_agents                      = false
  enable_cross_zone_restart          = true
  use_authoritative_project_metadata = false
  internal_runner_endpoint_version   = 7
}

run "accepts_operational_configuration" {
  command = plan

  assert {
    condition = (
      output.runner_service_account_email == "runner@runner-project.iam.gserviceaccount.com" &&
      output.environment_vm_service_account_email == "environment@runner-project.iam.gserviceaccount.com" &&
      toset(output.internal_runner_ips) == toset(["10.0.0.10", "10.0.0.11"])
    )
    error_message = "The restricted wrapper must accept operational configuration and use the pre-created service accounts."
  }
}
