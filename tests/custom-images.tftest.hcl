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

# Make cloud-init inspectable during plan without generating TLS identities.
override_resource {
  target          = tls_private_key.auth_proxy
  override_during = plan
  values = {
    private_key_pem = "synthetic-test-private-key"
  }
}

override_resource {
  target          = tls_self_signed_cert.auth_proxy
  override_during = plan
  values = {
    cert_pem = "synthetic-test-certificate"
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
      proxy_image         = "registry.example.com/team/proxy:release"
      prometheus_image    = "registry.example.com/team/prometheus:release"
      node_exporter_image = "registry.example.com/team/node-exporter:release"
      runner_image        = "us-docker.pkg.dev/gitpod-next-production/gitpod-next/gitpod-gcp-runner:kb-gcp-metrics-cves"
    }
  }

  assert {
    condition = (
      local.runner_uses_custom_image &&
      local.custom_runner_registry == "us-docker.pkg.dev/gitpod-next-production/gitpod-next/gitpod-gcp-runner" &&
      local.runner_image == var.custom_images.runner_image &&
      local.proxy_image == var.custom_images.proxy_image &&
      local.prometheus_image == var.custom_images.prometheus_image &&
      local.node_exporter_image == var.custom_images.node_exporter_image
    )
    error_message = "Preserve the full image path and registry port, removing only the tag or digest for the updater; keep the initial image unchanged."
  }
}

run "digest_image" {
  command = plan

  variables {
    custom_images = {
      proxy_image         = "registry.example.com/team/proxy@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      prometheus_image    = "registry.example.com/team/prometheus@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      node_exporter_image = "registry.example.com/team/node-exporter@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      runner_image        = "us-docker.pkg.dev/gitpod-next-production/gitpod-next/gitpod-gcp-runner@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    }
  }

  assert {
    condition = (
      local.runner_uses_custom_image &&
      local.custom_runner_registry == "us-docker.pkg.dev/gitpod-next-production/gitpod-next/gitpod-gcp-runner" &&
      local.runner_image == var.custom_images.runner_image &&
      local.proxy_image == var.custom_images.proxy_image &&
      local.prometheus_image == var.custom_images.prometheus_image &&
      local.node_exporter_image == var.custom_images.node_exporter_image
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
      proxy_image         = "registry.example.com/team/proxy"
      prometheus_image    = "registry.example.com/team/prometheus"
      node_exporter_image = "registry.example.com/team/node-exporter"
      runner_image        = "us-docker.pkg.dev/gitpod-next-production/gitpod-next/gitpod-gcp-runner"
    }
  }

  assert {
    condition = (
      local.runner_uses_custom_image &&
      local.custom_runner_registry == "us-docker.pkg.dev/gitpod-next-production/gitpod-next/gitpod-gcp-runner" &&
      local.runner_image == var.custom_images.runner_image &&
      local.proxy_image == var.custom_images.proxy_image &&
      local.prometheus_image == var.custom_images.prometheus_image &&
      local.node_exporter_image == var.custom_images.node_exporter_image
    )
    error_message = "Preserve the full image path and registry port, removing only the tag or digest for the updater; keep the initial image unchanged."
  }
}

run "registry_port_tagged" {
  command = plan

  variables {
    custom_images = {
      proxy_image         = "registry.example.com:5000/team/proxy:release"
      prometheus_image    = "registry.example.com:5000/team/prometheus:release"
      node_exporter_image = "registry.example.com:5000/team/node-exporter:release"
      runner_image        = "registry.example.com:5000/team/runner:release"
    }
  }

  assert {
    condition = (
      local.runner_uses_custom_image &&
      local.custom_runner_registry == "registry.example.com:5000/team/runner" &&
      local.runner_image == var.custom_images.runner_image &&
      local.proxy_image == var.custom_images.proxy_image &&
      local.prometheus_image == var.custom_images.prometheus_image &&
      local.node_exporter_image == var.custom_images.node_exporter_image
    )
    error_message = "Preserve the full image path and registry port, removing only the tag or digest for the updater; keep the initial image unchanged."
  }
}

run "registry_port_digest" {
  command = plan

  variables {
    custom_images = {
      proxy_image         = "registry.example.com:5000/team/proxy@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      prometheus_image    = "registry.example.com:5000/team/prometheus@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      node_exporter_image = "registry.example.com:5000/team/node-exporter@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      runner_image        = "registry.example.com:5000/team/runner@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    }
  }

  assert {
    condition = (
      local.runner_uses_custom_image &&
      local.custom_runner_registry == "registry.example.com:5000/team/runner" &&
      local.runner_image == var.custom_images.runner_image &&
      local.proxy_image == var.custom_images.proxy_image &&
      local.prometheus_image == var.custom_images.prometheus_image &&
      local.node_exporter_image == var.custom_images.node_exporter_image
    )
    error_message = "Preserve the full image path and registry port, removing only the tag or digest for the updater; keep the initial image unchanged."
  }
}

run "registry_port_untagged" {
  command = plan

  variables {
    custom_images = {
      proxy_image         = "registry.example.com:5000/team/proxy"
      prometheus_image    = "registry.example.com:5000/team/prometheus"
      node_exporter_image = "registry.example.com:5000/team/node-exporter"
      runner_image        = "registry.example.com:5000/team/runner"
    }
  }

  assert {
    condition = (
      local.runner_uses_custom_image &&
      local.custom_runner_registry == "registry.example.com:5000/team/runner" &&
      local.runner_image == var.custom_images.runner_image &&
      local.proxy_image == var.custom_images.proxy_image &&
      local.prometheus_image == var.custom_images.prometheus_image &&
      local.node_exporter_image == var.custom_images.node_exporter_image
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
      local.runner_image == local.default_runner_image &&
      local.proxy_image == local.default_proxy_image &&
      local.prometheus_image == local.default_prometheus_image &&
      local.node_exporter_image == local.default_node_exporter_image
    )
    error_message = "Without a custom runner image, use the default image and omit the custom registry flag."
  }
}

run "all_custom_images_in_cloud_init" {
  command = plan

  variables {
    custom_images = {
      runner_image        = "registry.example.com:5000/team/runner:release"
      proxy_image         = "registry.example.com:5000/team/proxy@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      prometheus_image    = "registry.example.com:5000/team/prometheus"
      node_exporter_image = "registry.example.com:5000/team/node-exporter:metrics"
      docker_config_json  = "{\"auths\":{\"registry.example.com:5000\":{\"auth\":\"c3ludGhldGljOnRlc3Q=\"}}}"
      insecure            = true
    }
  }

  assert {
    condition = alltrue([
      for service, image in {
        gitpod-runner     = var.custom_images.runner_image
        gitpod-auth-proxy = var.custom_images.runner_image
        prometheus        = var.custom_images.prometheus_image
        node-exporter     = var.custom_images.node_exporter_image
        } : strcontains(one([
          for file in yamldecode(data.cloudinit_config.runner.part[0].content).write_files :
          file.content if file.path == "/var/lib/systemd/system/${service}.service"
      ]), "\n  ${image} ")
    ])
    error_message = "Runner VM services must use the exact custom references; auth-proxy must share the runner image."
  }

  assert {
    condition = alltrue([
      for service, image in {
        gitpod-proxy  = var.custom_images.proxy_image
        prometheus    = var.custom_images.prometheus_image
        node-exporter = var.custom_images.node_exporter_image
        } : strcontains(one([
          for file in yamldecode(data.cloudinit_config.proxy[0].part[0].content).write_files :
          file.content if file.path == "/var/lib/systemd/system/${service}.service"
      ]), "\n  ${image} ")
    ])
    error_message = "Proxy VM services must use the exact custom proxy and metrics image references."
  }

  assert {
    condition = (
      strcontains(data.cloudinit_config.runner.part[0].content, "--custom-image-registry=registry.example.com:5000/team/runner") &&
      local.custom_image_registries == toset(["registry.example.com:5000"]) &&
      google_storage_bucket_object.docker_config[0].content == var.custom_images.docker_config_json &&
      alltrue(flatten([
        for content in [data.cloudinit_config.runner.part[0].content, data.cloudinit_config.proxy[0].part[0].content] : [
          for file in yamldecode(content).write_files :
          strcontains(file.content, "ExecStart=/usr/bin/docker --config /var/lib/gitpod/docker-config run")
          if contains(["gitpod-runner.service", "gitpod-auth-proxy.service", "gitpod-proxy.service", "prometheus.service", "node-exporter.service"], basename(file.path))
        ]
      ]))
    )
    error_message = "All custom containers must use the configured Docker credentials, preserving registry ports; only the runner updater gets a versionless image path."
  }
}

run "custom_sidecars_with_default_runner" {
  command = plan

  variables {
    custom_images = {
      proxy_image         = "registry.example.com/team/proxy:release"
      prometheus_image    = "registry.example.com/team/prometheus:metrics"
      node_exporter_image = "registry.example.com/team/node-exporter:metrics"
    }
  }

  assert {
    condition = (
      !local.runner_uses_custom_image &&
      local.custom_runner_registry == "" &&
      local.runner_image == local.default_runner_image &&
      local.proxy_image == var.custom_images.proxy_image &&
      local.prometheus_image == var.custom_images.prometheus_image &&
      local.node_exporter_image == var.custom_images.node_exporter_image &&
      !strcontains(data.cloudinit_config.runner.part[0].content, "--custom-image-registry=")
    )
    error_message = "Custom proxy and metrics images must not change the default runner image or enable its custom-registry updater flag."
  }
}
