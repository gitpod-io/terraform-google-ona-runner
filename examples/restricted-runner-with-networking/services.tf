locals {
  base_required_services = toset([
    "artifactregistry.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "dns.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "networkconnectivity.googleapis.com",
    "pubsub.googleapis.com",
    "redis.googleapis.com",
    "secretmanager.googleapis.com",
    "servicedirectory.googleapis.com",
    "storage.googleapis.com",
  ])

  required_services = setunion(
    local.base_required_services,
    var.enable_url_filtering ? toset(["networksecurity.googleapis.com"]) : toset([]),
  )
}

resource "google_project_service" "required" {
  for_each = local.required_services

  project = var.project_id
  service = each.value

  disable_on_destroy         = false
  disable_dependent_services = false
}
