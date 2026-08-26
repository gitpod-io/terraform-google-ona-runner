mock_provider "google" {
  override_during = plan
}

mock_provider "google-beta" {
  override_during = plan
}

mock_provider "tls" {
  override_during = plan
}

mock_provider "null" {
  override_during = plan
}

mock_provider "time" {
  override_during = plan
}

run "apply_legacy_docker_configuration" {
  command   = apply
  state_key = "docker-credentials-migration"

  module {
    source = "./tests/fixtures/legacy-docker-credentials"
  }

  variables {
    runner_id  = "00000000-0000-0000-0000-000000000000"
    project_id = "test-project"
    region     = "us-central1"
    docker_config_json = jsonencode({
      auths = {
        "registry.example.com" = {
          auth = "non-secret-test-value"
        }
      }
    })
  }

  assert {
    condition     = google_storage_bucket_object.docker_config[0].bucket == google_storage_bucket.runner_assets.name
    error_message = "The legacy fixture must store docker-config.json in runner assets."
  }
}

run "plan_docker_configuration_migration" {
  command   = plan
  state_key = "docker-credentials-migration"

  variables {
    runner_id     = "00000000-0000-0000-0000-000000000000"
    runner_name   = "test-runner"
    runner_domain = "runner.example.com"
    runner_token  = "non-secret-test-token"
    project_id    = "test-project"
    region        = "us-central1"
    zones         = ["us-central1-a"]
    custom_images = {
      docker_config_json = jsonencode({
        auths = {
          "registry.example.com" = {
            auth = "non-secret-test-value"
          }
        }
      })
    }
    pre_created_service_accounts = {
      runner              = "runner@test-project.iam.gserviceaccount.com"
      environment_vm      = "environment@test-project.iam.gserviceaccount.com"
      proxy_vm            = "proxy@test-project.iam.gserviceaccount.com"
      attach_iam_policies = false
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

  override_resource {
    target = tls_private_key.auth_proxy
    values = {
      private_key_pem = "non-secret-test-private-key"
    }
  }

  override_resource {
    target = tls_self_signed_cert.auth_proxy
    values = {
      cert_pem = "non-secret-test-certificate"
    }
  }

  assert {
    condition     = google_storage_bucket.runner_assets.name == "00000000-0000-0000-0000-000000000000-runner-assets"
    error_message = "Migrating Docker credentials must retain the runner assets bucket."
  }

  assert {
    condition     = google_storage_bucket.docker_credentials[0].name == "00000000-0000-0000-0000-000000000000-docker-credentials"
    error_message = "The migration must create the dedicated Docker credentials bucket."
  }

  assert {
    condition     = google_storage_bucket_object.docker_config_private[0].bucket == google_storage_bucket.docker_credentials[0].name
    error_message = "The migration must create a new object in the credential bucket."
  }

  assert {
    condition     = google_storage_bucket_object.docker_config[0].bucket == google_storage_bucket.runner_assets.name
    error_message = "The migration must not move the legacy object across buckets in place."
  }

  assert {
    condition     = nonsensitive(google_storage_bucket_object.docker_config[0].content) == jsonencode({ auths = {} })
    error_message = "The migration must sanitize the legacy object with an empty Docker configuration."
  }

  assert {
    condition     = google_storage_bucket_iam_member.runner_docker_credentials_access[0].member == "serviceAccount:runner@test-project.iam.gserviceaccount.com" && google_storage_bucket_iam_member.proxy_vm_docker_credentials_access[0].member == "serviceAccount:proxy@test-project.iam.gserviceaccount.com"
    error_message = "The migration plan must grant runner and proxy access to the credential bucket."
  }

  assert {
    condition     = google_compute_region_instance_group_manager.runner.wait_for_instances_status == "UPDATED" && google_compute_region_instance_group_manager.proxy.wait_for_instances_status == "UPDATED"
    error_message = "The migration must wait for every runner and proxy instance to reach the new template before sanitizing the legacy object."
  }
}
