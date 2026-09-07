mock_provider "google" {
  override_resource {
    target          = google_service_account.runner[0]
    override_during = plan
    values = {
      email = "test-runner-runner@test-project.iam.gserviceaccount.com"
      name  = "projects/test-project/serviceAccounts/test-runner-runner@test-project.iam.gserviceaccount.com"
    }
  }

  override_resource {
    target          = google_service_account.environment_vm[0]
    override_during = plan
    values = {
      email = "test-runner-env-vm@test-project.iam.gserviceaccount.com"
      name  = "projects/test-project/serviceAccounts/test-runner-env-vm@test-project.iam.gserviceaccount.com"
    }
  }

  override_resource {
    target          = google_service_account.proxy_vm[0]
    override_during = plan
    values = {
      email = "test-runner-proxy-vm@test-project.iam.gserviceaccount.com"
      name  = "projects/test-project/serviceAccounts/test-runner-proxy-vm@test-project.iam.gserviceaccount.com"
    }
  }

  override_data {
    target = data.google_project.current
    values = {
      number = "123456789"
    }
  }

  override_data {
    target = data.google_compute_subnetwork.runner_subnet
    values = {
      ip_cidr_range = "10.0.0.0/24"
    }
  }
}

mock_provider "google-beta" {}

mock_provider "tls" {
  override_resource {
    target          = tls_private_key.auth_proxy
    override_during = plan
    values = {
      private_key_pem = "non-secret-test-private-key"
    }
  }

  override_resource {
    target          = tls_self_signed_cert.auth_proxy
    override_during = plan
    values = {
      cert_pem = "non-secret-test-certificate"
    }
  }
}

variables {
  runner_id     = "00000000-0000-0000-0000-000000000000"
  runner_name   = "test-runner"
  runner_domain = "runner.example.com"
  runner_token  = "non-secret-test-token"
  project_id    = "test-project"
  region        = "us-central1"
  zones         = ["us-central1-a"]
  pre_created_service_accounts = {
    runner              = "runner-vm@test-project.iam.gserviceaccount.com"
    environment_vm      = "environment-vm@test-project.iam.gserviceaccount.com"
    proxy_vm            = "proxy-vm@test-project.iam.gserviceaccount.com"
    attach_iam_policies = true
  }
}

run "module_managed_default" {
  command = plan

  assert {
    condition     = length(google_artifact_registry_repository_iam_member.environment_vm_reader) == 1
    error_message = "The default must grant access only to the module-created devcontainer cache."
  }

  assert {
    condition     = google_artifact_registry_repository_iam_member.environment_vm_reader["test-project/us-central1/gitpod-cache-00000000-0000-0000-0000-000000000000"].repository == google_artifact_registry_repository.runner.repository_id
    error_message = "The default environment grant must target the module-created cache repository."
  }

  assert {
    condition     = google_artifact_registry_repository_iam_member.environment_vm_reader["test-project/us-central1/gitpod-cache-00000000-0000-0000-0000-000000000000"].member == "serviceAccount:environment-vm@test-project.iam.gserviceaccount.com"
    error_message = "Repository access must use the configured environment VM identity."
  }
}

run "approved_same_and_cross_project_repositories" {
  command = plan

  variables {
    environment_vm_artifact_registry_repositories = [
      {
        project_id    = "test-project"
        location      = "us-central1"
        repository_id = "private-devcontainers"
      },
      {
        project_id    = "shared-images-project"
        location      = "europe-west1"
        repository_id = "approved-images"
      }
    ]
  }

  assert {
    condition     = length(google_artifact_registry_repository_iam_member.environment_vm_reader) == 3
    error_message = "The cache and both approved repositories must receive reader grants."
  }

  assert {
    condition     = google_artifact_registry_repository_iam_member.environment_vm_reader["shared-images-project/europe-west1/approved-images"].project == "shared-images-project"
    error_message = "Approved repositories must support a project different from the runner project."
  }

  assert {
    condition     = google_artifact_registry_repository_iam_member.environment_vm_reader["shared-images-project/europe-west1/approved-images"].location == "europe-west1"
    error_message = "Approved repositories must preserve their configured location."
  }
}

run "pre_created_environment_identity" {
  command = plan

  assert {
    condition     = length(google_service_account.environment_vm) == 0
    error_message = "A pre-created environment service account must not be recreated."
  }

  assert {
    condition     = alltrue([for binding in google_artifact_registry_repository_iam_member.environment_vm_reader : binding.member == "serviceAccount:environment-vm@test-project.iam.gserviceaccount.com"])
    error_message = "Every approved repository must be granted to the pre-created environment identity."
  }
}

run "module_created_environment_identity" {
  command = plan

  variables {
    pre_created_service_accounts = {
      attach_iam_policies = false
    }
  }

  assert {
    condition     = length(google_service_account.environment_vm) == 1
    error_message = "The default configuration must create the environment service account."
  }

  assert {
    condition     = length(google_artifact_registry_repository_iam_member.environment_vm_reader) == 1
    error_message = "A module-created environment identity must receive access to the cache repository."
  }

  assert {
    condition     = google_artifact_registry_repository_iam_member.environment_vm_reader["test-project/us-central1/gitpod-cache-00000000-0000-0000-0000-000000000000"].member == "serviceAccount:test-runner-env-vm@test-project.iam.gserviceaccount.com"
    error_message = "The cache grant must use the module-created environment identity."
  }
}

run "customer_managed_iam" {
  command = plan

  variables {
    environment_vm_artifact_registry_repositories = [
      {
        project_id    = "shared-images-project"
        location      = "europe-west1"
        repository_id = "approved-images"
      }
    ]
    pre_created_service_accounts = {
      runner              = "runner-vm@test-project.iam.gserviceaccount.com"
      environment_vm      = "environment-vm@test-project.iam.gserviceaccount.com"
      proxy_vm            = "proxy-vm@test-project.iam.gserviceaccount.com"
      attach_iam_policies = false
    }
  }

  assert {
    condition     = length(google_artifact_registry_repository_iam_member.environment_vm_reader) == 0
    error_message = "Customer-managed IAM mode must not create repository IAM bindings."
  }

  assert {
    condition     = length(google_project_iam_member.env_vm_logging) == 0 && length(google_project_iam_member.env_vm_monitoring) == 0
    error_message = "Customer-managed IAM mode must preserve the existing project-IAM behavior."
  }
}
