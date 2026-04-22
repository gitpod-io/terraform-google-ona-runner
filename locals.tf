locals {
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
  default_runner_image = "us-docker.pkg.dev/gitpod-next-production/gitpod-next/gitpod-gcp-runner:20260422.644"
  default_proxy_image  = "us-docker.pkg.dev/gitpod-next-production/gitpod-next/gitpod-proxy:20260422.644"

  default_prometheus_image    = "us-docker.pkg.dev/gitpod-next-production/gitpod-next/prometheus:v3.11.1"
  default_node_exporter_image = "us-docker.pkg.dev/gitpod-next-production/gitpod-next/node-exporter:v1.11.1"

  # Final images (custom or default)
  runner_image        = var.custom_images.runner_image != "" ? var.custom_images.runner_image : local.default_runner_image
  proxy_image         = var.custom_images.proxy_image != "" ? var.custom_images.proxy_image : local.default_proxy_image
  prometheus_image    = var.custom_images.prometheus_image != "" ? var.custom_images.prometheus_image : local.default_prometheus_image
  node_exporter_image = var.custom_images.node_exporter_image != "" ? var.custom_images.node_exporter_image : local.default_node_exporter_image

  runner_dev_image = var.development_version != "" ? "us-docker.pkg.dev/gitpod-next-production/gitpod-next/gitpod-gcp-runner:${var.development_version}" : local.runner_image

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
