# Health validation for MIGs and backend services
# Fails terraform apply if instances are not healthy

data "google_client_config" "health_validation" {}

# Local values for health validation that work with both user auth and service account auth
locals {
  health_validation_project       = var.project_id
  health_validation_token         = data.google_client_config.health_validation.access_token
  health_validation_proxy_igms    = concat([google_compute_region_instance_group_manager.proxy.self_link], [for _, mig in google_compute_region_instance_group_manager.proxy_additional : mig.self_link])
  health_validation_proxy_groups  = concat([google_compute_region_instance_group_manager.proxy.instance_group], [for _, mig in google_compute_region_instance_group_manager.proxy_additional : mig.instance_group])
  health_validation_proxy_regions = concat([var.region], [for region, _ in google_compute_region_instance_group_manager.proxy_additional : region])
  health_validation_internal_proxy_igms = local.internal_cross_region_loadbalancer ? local.health_validation_proxy_igms : [
    google_compute_region_instance_group_manager.proxy.self_link
  ]
  health_validation_internal_proxy_groups = local.internal_cross_region_loadbalancer ? local.health_validation_proxy_groups : [
    google_compute_region_instance_group_manager.proxy.instance_group
  ]
  health_validation_internal_proxy_regions = local.internal_cross_region_loadbalancer ? local.health_validation_proxy_regions : [
    var.region
  ]
}

# Wait for MIGs to be fully provisioned before health validation
resource "time_sleep" "wait_for_mig_provisioning" {
  depends_on = [
    google_compute_region_instance_group_manager.runner,
    google_compute_region_instance_group_manager.proxy,
    google_compute_region_instance_group_manager.proxy_additional,
    google_compute_region_autoscaler.runner,
    google_compute_region_autoscaler.proxy,
    google_compute_region_autoscaler.proxy_additional
  ]

  create_duration = "2m" # Wait 2 minutes for initial provisioning
}

# Health validation for external load balancer
resource "null_resource" "health_validation_external" {
  count = var.loadbalancer_type == "external" ? 1 : 0

  triggers = {
    runner_igm           = google_compute_region_instance_group_manager.runner.self_link
    runner_target        = tostring(google_compute_region_autoscaler.runner.autoscaling_policy[0].min_replicas)
    proxy_igm            = google_compute_region_instance_group_manager.proxy.self_link
    proxy_igms           = join(",", local.health_validation_proxy_igms)
    proxy_regions        = join(",", local.health_validation_proxy_regions)
    proxy_target         = tostring(google_compute_region_autoscaler.proxy.autoscaling_policy[0].min_replicas)
    proxy_instance_group = google_compute_region_instance_group_manager.proxy.instance_group
    proxy_groups         = join(",", local.health_validation_proxy_groups)
    proxy_backend_ssl    = google_compute_backend_service.proxy[0].self_link
    proxy_backend_http   = google_compute_backend_service.proxy_http[0].self_link
    token_fingerprint    = substr(local.health_validation_token, 0, 16)
    script_version       = "v7"
  }

  provisioner "local-exec" {
    command = "echo 'Starting health validation...' && /bin/bash ${path.module}/health-check.sh"
    environment = {
      RUNNER_IGM                 = google_compute_region_instance_group_manager.runner.self_link
      RUNNER_TARGET              = google_compute_region_autoscaler.runner.autoscaling_policy[0].min_replicas
      PROXY_IGM                  = google_compute_region_instance_group_manager.proxy.self_link
      PROXY_IGMS                 = join(",", local.health_validation_proxy_igms)
      PROXY_REGIONS              = join(",", local.health_validation_proxy_regions)
      PROXY_TARGET               = google_compute_region_autoscaler.proxy.autoscaling_policy[0].min_replicas
      PROXY_GROUP                = google_compute_region_instance_group_manager.proxy.instance_group
      PROXY_GROUPS               = join(",", local.health_validation_proxy_groups)
      PROXY_BACKEND_SSL          = google_compute_backend_service.proxy[0].self_link
      PROXY_BACKEND_HTTP         = google_compute_backend_service.proxy_http[0].self_link
      GOOGLE_OAUTH_TOKEN         = local.health_validation_token
      PROJECT_ID                 = local.health_validation_project
      HEALTH_CHECK_TIMEOUT       = 1800 # 30 minutes
      HEALTH_CHECK_INITIAL_DELAY = 120  # 2 minutes initial delay for MIG provisioning
    }
  }

  depends_on = [
    time_sleep.wait_for_mig_provisioning,
    google_compute_health_check.runner,
    google_compute_backend_service.proxy[0],
    google_compute_backend_service.proxy_http[0],
    google_compute_health_check.proxy_http[0],
    google_compute_health_check.proxy_ssl[0]
  ]
}

# Health validation for internal load balancer
resource "null_resource" "health_validation_internal" {
  count = var.loadbalancer_type == "internal" ? 1 : 0

  triggers = {
    runner_igm           = google_compute_region_instance_group_manager.runner.self_link
    runner_target        = tostring(google_compute_region_autoscaler.runner.autoscaling_policy[0].min_replicas)
    proxy_igm            = google_compute_region_instance_group_manager.proxy.self_link
    proxy_igms           = join(",", local.health_validation_internal_proxy_igms)
    proxy_regions        = join(",", local.health_validation_internal_proxy_regions)
    proxy_target         = tostring(google_compute_region_autoscaler.proxy.autoscaling_policy[0].min_replicas)
    proxy_instance_group = google_compute_region_instance_group_manager.proxy.instance_group
    proxy_groups         = join(",", local.health_validation_internal_proxy_groups)
    proxy_backend_ssl    = local.internal_cross_region_loadbalancer ? google_compute_backend_service.proxy_internal_cross_region[0].self_link : ""
    proxy_backend_http   = ""
    token_fingerprint    = substr(local.health_validation_token, 0, 16)
    script_version       = "v7"
  }

  provisioner "local-exec" {
    command = "echo 'Starting health validation...' && /bin/bash ${path.module}/health-check.sh"
    environment = {
      RUNNER_IGM                 = google_compute_region_instance_group_manager.runner.self_link
      RUNNER_TARGET              = google_compute_region_autoscaler.runner.autoscaling_policy[0].min_replicas
      PROXY_IGM                  = google_compute_region_instance_group_manager.proxy.self_link
      PROXY_IGMS                 = join(",", local.health_validation_internal_proxy_igms)
      PROXY_REGIONS              = join(",", local.health_validation_internal_proxy_regions)
      PROXY_TARGET               = google_compute_region_autoscaler.proxy.autoscaling_policy[0].min_replicas
      PROXY_GROUP                = google_compute_region_instance_group_manager.proxy.instance_group
      PROXY_GROUPS               = join(",", local.health_validation_internal_proxy_groups)
      PROXY_BACKEND_SSL          = local.internal_cross_region_loadbalancer ? google_compute_backend_service.proxy_internal_cross_region[0].self_link : ""
      PROXY_BACKEND_HTTP         = ""
      GOOGLE_OAUTH_TOKEN         = local.health_validation_token
      PROJECT_ID                 = local.health_validation_project
      HEALTH_CHECK_TIMEOUT       = 1800 # 30 minutes
      HEALTH_CHECK_INITIAL_DELAY = 120  # 2 minutes initial delay for MIG provisioning
    }
  }

  depends_on = [
    time_sleep.wait_for_mig_provisioning,
    google_compute_health_check.runner,
    google_compute_region_health_check.proxy_ssl_internal,
    google_compute_region_backend_service.proxy_internal,
    google_compute_health_check.proxy_ssl_internal_cross_region,
    google_compute_backend_service.proxy_internal_cross_region
  ]
}
