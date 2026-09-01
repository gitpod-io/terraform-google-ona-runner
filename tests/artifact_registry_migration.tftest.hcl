mock_provider "google" {
  override_resource {
    target          = google_service_account.environment_vm[0]
    override_during = plan
    values = {
      email = "test-runner-env-vm@test-project.iam.gserviceaccount.com"
      name  = "projects/test-project/serviceAccounts/test-runner-env-vm@test-project.iam.gserviceaccount.com"
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

run "apply_previous_project_binding" {
  command   = apply
  state_key = "artifact-registry-migration"

  module {
    source = "./tests/fixtures/legacy-artifact-registry-iam"
  }

  variables {
    project_id              = "test-project"
    environment_vm_sa_email = "environment-vm@test-project.iam.gserviceaccount.com"
  }

  assert {
    condition     = google_project_iam_member.env_vm_artifact_registry.role == "roles/artifactregistry.reader"
    error_message = "The migration fixture must model the previous project-wide reader grant."
  }
}

run "plan_repository_restriction_upgrade" {
  command   = plan
  state_key = "artifact-registry-migration"

  variables {
    runner_id     = "00000000-0000-0000-0000-000000000000"
    runner_name   = "test-runner"
    runner_domain = "runner.example.com"
    runner_token  = "non-secret-test-token"
    project_id    = "test-project"
    region        = "us-central1"
    zones         = ["us-central1-a"]
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
      attach_iam_policies = true
    }
  }

  assert {
    condition     = length(google_artifact_registry_repository_iam_member.environment_vm_reader) == 2
    error_message = "The upgrade must add repository grants for the cache and approved cross-project repository."
  }

  assert {
    condition     = google_artifact_registry_repository_iam_member.environment_vm_reader["shared-images-project/europe-west1/approved-images"].role == "roles/artifactregistry.reader"
    error_message = "The upgrade must retain reader access on explicitly approved repositories."
  }
}
