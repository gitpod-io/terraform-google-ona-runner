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
    runner              = "runner@test-project.iam.gserviceaccount.com"
    environment_vm      = "environment@test-project.iam.gserviceaccount.com"
    proxy_vm            = "proxy@test-project.iam.gserviceaccount.com"
    attach_iam_policies = false
  }
}

run "docker_configuration_disabled" {
  command = plan

  assert {
    condition     = length(google_storage_bucket.docker_credentials) == 0
    error_message = "The Docker credential bucket must be optional."
  }

  assert {
    condition     = length(google_storage_bucket_object.docker_config_private) == 0 && length(google_storage_bucket_object.docker_config) == 0
    error_message = "The Docker configuration objects must be optional."
  }

  assert {
    condition     = length(google_storage_bucket_iam_member.runner_docker_credentials_access) == 0 && length(google_storage_bucket_iam_member.proxy_vm_docker_credentials_access) == 0
    error_message = "Credential readers must not be created without a Docker configuration."
  }
}

run "docker_configuration_enabled" {
  command = plan

  variables {
    custom_images = {
      docker_config_json = jsonencode({
        auths = {
          "registry.example.com" = {
            auth = "non-secret-test-value"
          }
        }
      })
    }
  }

  assert {
    condition     = google_storage_bucket.docker_credentials[0].name == "00000000-0000-0000-0000-000000000000-docker-credentials"
    error_message = "Docker credentials must use the dedicated bucket."
  }

  assert {
    condition     = google_storage_bucket.docker_credentials[0].uniform_bucket_level_access && google_storage_bucket.docker_credentials[0].public_access_prevention == "enforced"
    error_message = "The credential bucket must enforce private uniform access."
  }

  assert {
    condition     = google_storage_bucket_object.docker_config_private[0].bucket == google_storage_bucket.docker_credentials[0].name
    error_message = "docker-config.json must not be stored in runner assets."
  }

  assert {
    condition     = google_storage_bucket_object.docker_config[0].bucket == google_storage_bucket.runner_assets.name && nonsensitive(google_storage_bucket_object.docker_config[0].content) == jsonencode({ auths = {} })
    error_message = "The legacy object must contain only an empty Docker configuration."
  }

  assert {
    condition     = google_storage_bucket_iam_member.runner_docker_credentials_access[0].role == "roles/storage.objectViewer" && google_storage_bucket_iam_member.runner_docker_credentials_access[0].member == "serviceAccount:runner@test-project.iam.gserviceaccount.com"
    error_message = "The runner identity must retain read-only credential access."
  }

  assert {
    condition     = google_storage_bucket_iam_member.proxy_vm_docker_credentials_access[0].role == "roles/storage.objectViewer" && google_storage_bucket_iam_member.proxy_vm_docker_credentials_access[0].member == "serviceAccount:proxy@test-project.iam.gserviceaccount.com"
    error_message = "The proxy identity must retain read-only credential access."
  }

  assert {
    condition     = google_storage_bucket_iam_member.env_vm_runner_assets_access.bucket == google_storage_bucket.runner_assets.name && google_storage_bucket_iam_member.env_vm_runner_assets_access.bucket != google_storage_bucket.docker_credentials[0].name
    error_message = "Environment VMs must remain limited to non-secret runner assets."
  }

  assert {
    condition     = strcontains(nonsensitive(data.cloudinit_config.runner.part[0].content), google_storage_bucket.docker_credentials[0].name) && strcontains(nonsensitive(data.cloudinit_config.proxy.part[0].content), google_storage_bucket.docker_credentials[0].name) && strcontains(nonsensitive(data.cloudinit_config.runner.part[0].content), "Docker config download attempt") && strcontains(nonsensitive(data.cloudinit_config.proxy.part[0].content), "Docker config download attempt")
    error_message = "Runner and proxy bootstrap must reference the credential bucket and retry downloads while IAM propagates."
  }
}

run "pre_created_service_accounts_with_external_project_iam" {
  command = plan

  variables {
    custom_images = {
      docker_config_json = jsonencode({ auths = {} })
    }
    pre_created_service_accounts = {
      runner              = "runner@test-project.iam.gserviceaccount.com"
      environment_vm      = "environment@test-project.iam.gserviceaccount.com"
      proxy_vm            = "proxy@test-project.iam.gserviceaccount.com"
      attach_iam_policies = false
    }
  }

  assert {
    condition     = length(google_service_account.runner) == 0 && length(google_service_account.environment_vm) == 0 && length(google_service_account.proxy_vm) == 0
    error_message = "Pre-created identities must not be recreated."
  }

  assert {
    condition     = google_storage_bucket_iam_member.runner_docker_credentials_access[0].member == "serviceAccount:runner@test-project.iam.gserviceaccount.com" && google_storage_bucket_iam_member.proxy_vm_docker_credentials_access[0].member == "serviceAccount:proxy@test-project.iam.gserviceaccount.com"
    error_message = "Resource-specific credential access must support pre-created identities."
  }

  assert {
    condition     = google_storage_bucket_iam_member.env_vm_runner_assets_access.member == "serviceAccount:environment@test-project.iam.gserviceaccount.com" && google_storage_bucket_iam_member.env_vm_runner_assets_access.bucket != google_storage_bucket.docker_credentials[0].name
    error_message = "The pre-created environment identity must not receive credential access."
  }

  assert {
    condition     = length(google_project_iam_member.runner_cp_custom_role) == 0 && length(google_project_iam_member.proxy_vm_compute) == 0
    error_message = "attach_iam_policies=false must continue to leave project IAM to the customer."
  }
}

run "module_created_service_accounts" {
  command = plan

  variables {
    custom_images = {
      docker_config_json = jsonencode({ auths = {} })
    }
    pre_created_service_accounts = {
      attach_iam_policies = false
    }
  }

  assert {
    condition     = length(google_service_account.runner) == 1 && length(google_service_account.environment_vm) == 1 && length(google_service_account.proxy_vm) == 1
    error_message = "The default configuration must continue to create all three identities."
  }

  assert {
    condition     = google_storage_bucket_iam_member.runner_docker_credentials_access[0].role == "roles/storage.objectViewer" && google_storage_bucket_iam_member.proxy_vm_docker_credentials_access[0].role == "roles/storage.objectViewer"
    error_message = "Module-created runner and proxy identities must receive read-only credential access."
  }
}
