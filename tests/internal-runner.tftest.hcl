# Ephemeral resource schemas require real providers, even with resource overrides.
# Data reads are overridden below; these plan tests use no cloud credentials.
provider "google" {
  project      = "runner-project"
  access_token = "unused-plan-test-token"
}
provider "google-beta" {
  project      = "runner-project"
  access_token = "unused-plan-test-token"
}
mock_provider "cloudinit" {}
mock_provider "null" {}
mock_provider "random" {}
mock_provider "time" {}
provider "tls" {}

override_data {
  target = data.google_project.current
  values = {
    number = "123456789012"
  }
}

override_data {
  target = data.google_compute_subnetwork.runner_subnet
  values = {
    ip_cidr_range = "10.0.0.0/24"
  }
}

variables {
  project_id         = "runner-project"
  runner_id          = "00000000-0000-4000-8000-000000000001"
  runner_name        = "test-runner"
  runner_domain      = "runner.example.com"
  runner_token       = "test-token"
  region             = "us-central1"
  zones              = ["us-central1-a"]
  vpc_name           = "runner-vpc"
  runner_subnet_name = "runner-subnet"
  certificate_id     = "projects/runner-project/locations/global/certificates/test"

  pre_created_service_accounts = {
    runner              = "runner@runner-project.iam.gserviceaccount.com"
    environment_vm      = "environment@runner-project.iam.gserviceaccount.com"
    proxy_vm            = "proxy-vm@runner-project.iam.gserviceaccount.com"
    attach_iam_policies = true
  }
}

override_resource {
  target          = google_compute_address.internal_runner[0]
  override_during = plan
  values = {
    address = "10.0.0.10"
  }
}

override_resource {
  target          = google_compute_address.internal_runner[1]
  override_during = plan
  values = {
    address = "10.0.0.11"
  }
}

override_resource {
  target          = tls_self_signed_cert.internal_runner[0]
  override_during = plan
  values = {
    cert_pem = "current-public-certificate"
  }
}

override_resource {
  target          = google_secret_manager_secret.internal_runner_tls["tls"]
  override_during = plan
  values = {
    id = "projects/runner-project/secrets/00000000-0000-4000-8000-000000000001-internal-llm-tls"
  }
}

override_resource {
  target          = google_secret_manager_secret_version.internal_runner_tls[0]
  override_during = plan
  values = {
    version = "7"
  }
}

run "disabled_by_default" {
  command = plan

  assert {
    condition = (
      length(google_compute_address.internal_runner) == 0 &&
      length(google_dns_managed_zone.internal_runner) == 0 &&
      length(google_dns_record_set.internal_runner) == 0 &&
      length(output.internal_runner_ips) == 0 &&
      output.internal_runner_hostname == null &&
      length(google_secret_manager_secret.internal_runner_tls) == 0 &&
      length(google_secret_manager_secret_version.internal_runner_key) == 0 &&
      length(google_secret_manager_secret_version.internal_runner_tls) == 0 &&
      length(tls_self_signed_cert.internal_runner) == 0 &&
      length(google_secret_manager_secret_iam_member.internal_runner_tls) == 0 &&
      output.internal_runner_tls == null
    )
    error_message = "Default deployments must not reserve runner IPs or create private DNS."
  }
}

run "private_runner_addresses" {
  command = plan

  variables {
    restrict_ingress = true
  }

  assert {
    condition = length(google_compute_address.internal_runner) == 2 && alltrue([
      for address in google_compute_address.internal_runner :
      address.address_type == "INTERNAL" &&
      address.project == "runner-project" &&
      address.region == "us-central1" &&
      address.subnetwork == "projects/runner-project/regions/us-central1/subnetworks/runner-subnet"
    ])
    error_message = "Both addresses must be internal reservations in the runner's project, region, and subnet."
  }

  assert {
    condition = (
      google_dns_managed_zone.internal_runner[0].visibility == "private" &&
      google_dns_managed_zone.internal_runner[0].project == "runner-project" &&
      one(google_dns_managed_zone.internal_runner[0].private_visibility_config[0].networks).network_url ==
      "https://www.googleapis.com/compute/v1/projects/runner-project/global/networks/runner-vpc"
    )
    error_message = "The private zone must be visible only to the configured VPC."
  }

  assert {
    condition = (
      google_dns_record_set.internal_runner[0].type == "A" &&
      google_dns_record_set.internal_runner[0].ttl == 10 &&
      google_dns_record_set.internal_runner[0].name == "runner.ona-00000000-0000-4000-8000-000000000001.internal." &&
      toset(google_dns_record_set.internal_runner[0].rrdatas) == toset(["10.0.0.10", "10.0.0.11"]) &&
      toset(output.internal_runner_ips) == toset(["10.0.0.10", "10.0.0.11"]) &&
      output.internal_runner_hostname == "runner.ona-00000000-0000-4000-8000-000000000001.internal"
    )
    error_message = "The runner hostname and outputs must expose both reserved IPs in a runner-specific namespace."
  }
}

run "shared_vpc" {
  command = plan

  variables {
    restrict_ingress = true
    vpc_project_id   = "network-project"
  }

  assert {
    condition = alltrue([
      for address in google_compute_address.internal_runner :
      address.project == "runner-project" &&
      address.subnetwork == "projects/network-project/regions/us-central1/subnetworks/runner-subnet"
    ])
    error_message = "Shared VPC reservations must belong to the runner project and use the host project's subnet."
  }

  assert {
    condition = (
      google_dns_managed_zone.internal_runner[0].project == "runner-project" &&
      one(google_dns_managed_zone.internal_runner[0].private_visibility_config[0].networks).network_url ==
      "https://www.googleapis.com/compute/v1/projects/network-project/global/networks/runner-vpc"
    )
    error_message = "The runner project's private zone must be bound to the Shared VPC host network."
  }
}

run "tls_identity_and_public_trust" {
  command = plan

  variables {
    restrict_ingress = true
  }

  assert {
    condition = (
      length(google_secret_manager_secret.internal_runner_tls) == 2 &&
      length(google_secret_manager_secret_version.internal_runner_key) == 1 &&
      length(google_secret_manager_secret_version.internal_runner_tls) == 1 &&
      length(tls_self_signed_cert.internal_runner) == 1 &&
      output.internal_runner_tls.certificate_pem == "current-public-certificate" &&
      tomap(output.internal_runner_tls.environment) == tomap({
        INTERNAL_RUNNER_ENDPOINT           = "https://runner.ona-00000000-0000-4000-8000-000000000001.internal:8089"
        INTERNAL_RUNNER_LLM_PORT           = "8089"
        INTERNAL_RUNNER_TLS_SECRET         = "00000000-0000-4000-8000-000000000001-internal-llm-tls"
        INTERNAL_RUNNER_TLS_SECRET_VERSION = "7"
      }) &&
      google_storage_bucket_object.trust_bundle[0].content == "current-public-certificate"
    )
    error_message = "The prepared runner configuration must pin the identity version and publish its public certificate."
  }

  assert {
    condition = (
      length(google_secret_manager_secret_iam_member.internal_runner_tls) == 1 &&
      google_secret_manager_secret_iam_member.internal_runner_tls[0].secret_id == "projects/runner-project/secrets/00000000-0000-4000-8000-000000000001-internal-llm-tls" &&
      google_secret_manager_secret_iam_member.internal_runner_tls[0].role == "roles/secretmanager.secretAccessor" &&
      google_secret_manager_secret_iam_member.internal_runner_tls[0].member == "serviceAccount:runner@runner-project.iam.gserviceaccount.com"
    )
    error_message = "The TLS identity grant must be scoped to the runner service account and pair secret."
  }
}

run "externally_managed_tls_iam" {
  command = plan

  variables {
    restrict_ingress = true
    pre_created_service_accounts = {
      runner              = "runner@runner-project.iam.gserviceaccount.com"
      environment_vm      = "environment@runner-project.iam.gserviceaccount.com"
      proxy_vm            = "proxy-vm@runner-project.iam.gserviceaccount.com"
      attach_iam_policies = false
    }
  }

  assert {
    condition     = length(google_secret_manager_secret_iam_member.internal_runner_tls) == 0
    error_message = "Externally managed IAM must not receive an automatic internal TLS grant."
  }
}

run "invalid_tls_version" {
  command = plan

  variables {
    internal_runner_tls_version = 0
  }

  expect_failures = [var.internal_runner_tls_version]
}
