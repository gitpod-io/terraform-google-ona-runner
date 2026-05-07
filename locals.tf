locals {
  module_version = trimspace(file("${path.module}/VERSION"))

  # VPC project ID - defaults to project_id if not specified (for Shared VPC support)
  vpc_project_id = var.vpc_project_id != "" ? var.vpc_project_id : var.project_id

  runner_labels = merge(var.labels, {
    managed-by         = "terraform"
    "gitpod-runner-id" = var.runner_id
    "gitpod-type"      = "runner"
  })

  proxy_labels = merge(var.labels, {
    managed-by         = "terraform"
    "gitpod-runner-id" = var.runner_id
    "gitpod-type"      = "proxy"
    component          = "proxy"
  })

  # Default images
  default_runner_image = "us-docker.pkg.dev/gitpod-next-production/gitpod-next/gitpod-gcp-runner:20260507.1014"
  default_proxy_image  = "us-docker.pkg.dev/gitpod-next-production/gitpod-next/gitpod-proxy:20260507.1014"

  default_prometheus_image    = "us-docker.pkg.dev/gitpod-next-production/gitpod-next/prometheus:v3.11.3"
  default_node_exporter_image = "us-docker.pkg.dev/gitpod-next-production/gitpod-next/node-exporter:v1.11.1"

  # Final images (custom or default)
  runner_image        = var.custom_images.runner_image != "" ? var.custom_images.runner_image : local.default_runner_image
  proxy_image         = var.custom_images.proxy_image != "" ? var.custom_images.proxy_image : local.default_proxy_image
  prometheus_image    = var.custom_images.prometheus_image != "" ? var.custom_images.prometheus_image : local.default_prometheus_image
  node_exporter_image = var.custom_images.node_exporter_image != "" ? var.custom_images.node_exporter_image : local.default_node_exporter_image

  runner_dev_image = var.development_version != "" ? "us-docker.pkg.dev/gitpod-next-production/gitpod-next/gitpod-gcp-runner:${var.development_version}" : local.runner_image

  # Container resource limits derived from VM machine type.
  # GCP standard machine types follow the pattern {family}-standard-{vcpus}
  # with memory = vcpus * 4 GB. We reserve ~25% for the host OS and Docker
  # daemon, then allocate the rest across containers.
  #
  # Aligned with EC2 Fargate runner limits:
  #   EC2 small:  1 vCPU /  3 GB task  → runner gets ~1 GB
  #   EC2 large:  8 vCPU / 16 GB task  → runner gets ~14 GB
  #   GCP small:  2 vCPU /  8 GB VM    → runner gets  5 GB / 1.25 CPU
  #   GCP regular: 4 vCPU / 16 GB VM   → runner gets 12 GB / 3 CPU

  runner_vcpus     = tonumber(regex("-(\\d+)$", var.runner_vm_config.machine_type)[0])
  runner_memory_gb = local.runner_vcpus * 4

  # Sidecar limits are fixed (small footprint). The main runner container
  # gets whatever remains after sidecars and OS overhead.
  runner_sidecar_memory_mb = 1792 # prometheus 1024 + auth-proxy 512 + node-exporter 256
  runner_sidecar_cpus      = 1.25 # prometheus 0.5 + auth-proxy 0.5 + node-exporter 0.25
  runner_os_reserve_mb     = 512

  runner_container_memory_mb = (local.runner_memory_gb * 1024) - local.runner_sidecar_memory_mb - local.runner_os_reserve_mb
  runner_container_cpus      = local.runner_vcpus - local.runner_sidecar_cpus

  proxy_vcpus     = tonumber(regex("-(\\d+)$", var.proxy_vm_config.machine_type)[0])
  proxy_memory_gb = local.proxy_vcpus * 4

  proxy_sidecar_memory_mb = 768 # prometheus 512 + node-exporter 256
  proxy_sidecar_cpus      = 0.5 # prometheus 0.25 + node-exporter 0.25
  proxy_os_reserve_mb     = 512

  proxy_container_memory_mb = (local.proxy_memory_gb * 1024) - local.proxy_sidecar_memory_mb - local.proxy_os_reserve_mb
  proxy_container_cpus      = local.proxy_vcpus - local.proxy_sidecar_cpus

  # Docker config handling
  docker_config_enabled     = var.custom_images.docker_config_json != ""
  docker_config_bucket_name = local.docker_config_enabled ? google_storage_bucket.runner_assets.name : ""
  docker_config_object_name = local.docker_config_enabled ? google_storage_bucket_object.docker_config[0].name : ""

  # Insecure registries handling
  insecure_registries_enabled = var.custom_images.insecure
  # Extract unique registry hosts from custom images (only non-empty images)
  custom_image_registries = var.custom_images.insecure ? toset(compact([
    var.custom_images.runner_image != "" ? regex("^([^/]+)", var.custom_images.runner_image)[0] : "",
    var.custom_images.proxy_image != "" ? regex("^([^/]+)", var.custom_images.proxy_image)[0] : "",
    var.custom_images.prometheus_image != "" ? regex("^([^/]+)", var.custom_images.prometheus_image)[0] : "",
    var.custom_images.node_exporter_image != "" ? regex("^([^/]+)", var.custom_images.node_exporter_image)[0] : ""
  ])) : toset([])
  # Convert to JSON array string for use in templates
  insecure_registries_json = jsonencode(tolist(local.custom_image_registries))

  # Custom image registry extraction for --custom-image-registry flag
  # Extract registry part (without tag) from runner image when custom image is used
  runner_uses_custom_image = var.custom_images.runner_image != ""
  custom_runner_registry   = local.runner_uses_custom_image ? regex("^([^/]+(?:/[^/]+)*?)(?:/[^/:]+)?(?:[:@].*)?$", var.custom_images.runner_image)[0] : ""

  # Centralized logs URL for container-based filtering
  logs_url = "https://console.cloud.google.com/logs/query;query=resource.type%%3D%%22gce_instance%%22%%0A%%2528jsonPayload.%%22cos.googleapis.com%%2Fcontainer_name%%22%%3D%%22gitpod-runner%%22%%20OR%%20jsonPayload.%%22cos.googleapis.com%%2Fcontainer_name%%22%%3D%%22gitpod-proxy%%22%%2529;duration=PT3H?project=${var.project_id}"

  # Determine if we're using pre-created service accounts (IAM team handles high-privilege operations)
  # Only considers the 3 active service accounts (runner, environment_vm, proxy_vm).
  using_pre_created_service_accounts = anytrue([
    var.pre_created_service_accounts.runner != "",
    var.pre_created_service_accounts.environment_vm != "",
    var.pre_created_service_accounts.proxy_vm != "",
  ])

  # Service account emails (either created or pre-created) - shared across all files
  runner_sa_email         = var.pre_created_service_accounts.runner != "" ? var.pre_created_service_accounts.runner : try(google_service_account.runner[0].email, "")
  environment_vm_sa_email = var.pre_created_service_accounts.environment_vm != "" ? var.pre_created_service_accounts.environment_vm : try(google_service_account.environment_vm[0].email, "")
  proxy_vm_sa_email       = var.pre_created_service_accounts.proxy_vm != "" ? var.pre_created_service_accounts.proxy_vm : try(google_service_account.proxy_vm[0].email, "")

  # Service account names for IAM bindings (full resource names)
  runner_sa_name         = var.pre_created_service_accounts.runner != "" ? "projects/${var.project_id}/serviceAccounts/${var.pre_created_service_accounts.runner}" : try(google_service_account.runner[0].name, "")
  environment_vm_sa_name = var.pre_created_service_accounts.environment_vm != "" ? "projects/${var.project_id}/serviceAccounts/${var.pre_created_service_accounts.environment_vm}" : try(google_service_account.environment_vm[0].name, "")
  proxy_vm_sa_name       = var.pre_created_service_accounts.proxy_vm != "" ? "projects/${var.project_id}/serviceAccounts/${var.pre_created_service_accounts.proxy_vm}" : try(google_service_account.proxy_vm[0].name, "")

}
