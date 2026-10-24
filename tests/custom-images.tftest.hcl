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

run "tagged_image" {
  command = plan

  variables {
    custom_images = {
      runner_image = "us-docker.pkg.dev/gitpod-next-production/gitpod-next/gitpod-gcp-runner:kb-gcp-metrics-cves"
    }
  }

  assert {
    condition = (
      local.runner_uses_custom_image &&
      local.custom_runner_registry == "us-docker.pkg.dev/gitpod-next-production/gitpod-next/gitpod-gcp-runner" &&
      local.runner_image == var.custom_images.runner_image
    )
    error_message = "Preserve the full image path and registry port, removing only the tag or digest for the updater; keep the initial image unchanged."
  }
}

run "digest_image" {
  command = plan

  variables {
    custom_images = {
      runner_image = "us-docker.pkg.dev/gitpod-next-production/gitpod-next/gitpod-gcp-runner@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    }
  }

  assert {
    condition = (
      local.runner_uses_custom_image &&
      local.custom_runner_registry == "us-docker.pkg.dev/gitpod-next-production/gitpod-next/gitpod-gcp-runner" &&
      local.runner_image == var.custom_images.runner_image
    )
    error_message = "Preserve the full image path and registry port, removing only the tag or digest for the updater; keep the initial image unchanged."
  }
}

run "tagged_digest_image" {
  command = plan

  variables {
    custom_images = {
      runner_image = "registry.example.com/team/runner:release@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    }
  }

  assert {
    condition = (
      local.runner_uses_custom_image &&
      local.custom_runner_registry == "registry.example.com/team/runner" &&
      local.runner_image == var.custom_images.runner_image
    )
    error_message = "Preserve the full image path and registry port, removing only the tag or digest for the updater; keep the initial image unchanged."
  }
}

run "untagged_image" {
  command = plan

  variables {
    custom_images = {
      runner_image = "us-docker.pkg.dev/gitpod-next-production/gitpod-next/gitpod-gcp-runner"
    }
  }

  assert {
    condition = (
      local.runner_uses_custom_image &&
      local.custom_runner_registry == "us-docker.pkg.dev/gitpod-next-production/gitpod-next/gitpod-gcp-runner" &&
      local.runner_image == var.custom_images.runner_image
    )
    error_message = "Preserve the full image path and registry port, removing only the tag or digest for the updater; keep the initial image unchanged."
  }
}

run "registry_port_tagged" {
  command = plan

  variables {
    custom_images = {
      runner_image = "registry.example.com:5000/team/runner:release"
    }
  }

  assert {
    condition = (
      local.runner_uses_custom_image &&
      local.custom_runner_registry == "registry.example.com:5000/team/runner" &&
      local.runner_image == var.custom_images.runner_image
    )
    error_message = "Preserve the full image path and registry port, removing only the tag or digest for the updater; keep the initial image unchanged."
  }
}

run "registry_port_digest" {
  command = plan

  variables {
    custom_images = {
      runner_image = "registry.example.com:5000/team/runner@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    }
  }

  assert {
    condition = (
      local.runner_uses_custom_image &&
      local.custom_runner_registry == "registry.example.com:5000/team/runner" &&
      local.runner_image == var.custom_images.runner_image
    )
    error_message = "Preserve the full image path and registry port, removing only the tag or digest for the updater; keep the initial image unchanged."
  }
}

run "registry_port_untagged" {
  command = plan

  variables {
    custom_images = {
      runner_image = "registry.example.com:5000/team/runner"
    }
  }

  assert {
    condition = (
      local.runner_uses_custom_image &&
      local.custom_runner_registry == "registry.example.com:5000/team/runner" &&
      local.runner_image == var.custom_images.runner_image
    )
    error_message = "Preserve the full image path and registry port, removing only the tag or digest for the updater; keep the initial image unchanged."
  }
}

run "registry_port_without_namespace" {
  command = plan

  variables {
    custom_images = {
      runner_image = "localhost:5000/runner:release"
    }
  }

  assert {
    condition = (
      local.runner_uses_custom_image &&
      local.custom_runner_registry == "localhost:5000/runner" &&
      local.runner_image == var.custom_images.runner_image
    )
    error_message = "Preserve the full image path and registry port, removing only the tag or digest for the updater; keep the initial image unchanged."
  }
}

run "short_tagged_image" {
  command = plan

  variables {
    custom_images = {
      runner_image = "runner:release"
    }
  }

  assert {
    condition = (
      local.runner_uses_custom_image &&
      local.custom_runner_registry == "runner" &&
      local.runner_image == var.custom_images.runner_image
    )
    error_message = "Preserve the full image path and registry port, removing only the tag or digest for the updater; keep the initial image unchanged."
  }
}

run "short_untagged_image" {
  command = plan

  variables {
    custom_images = {
      runner_image = "runner"
    }
  }

  assert {
    condition = (
      local.runner_uses_custom_image &&
      local.custom_runner_registry == "runner" &&
      local.runner_image == var.custom_images.runner_image
    )
    error_message = "Preserve the full image path and registry port, removing only the tag or digest for the updater; keep the initial image unchanged."
  }
}

run "default_image" {
  command = plan

  assert {
    condition = (
      !local.runner_uses_custom_image &&
      local.custom_runner_registry == "" &&
      local.runner_image == local.default_runner_image
    )
    error_message = "Without a custom runner image, use the default image and omit the custom registry flag."
  }
}
