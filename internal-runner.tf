resource "google_compute_address" "internal_runner" {
  count = var.restrict_ingress ? 2 : 0

  project      = var.project_id
  name         = "${var.runner_name}-internal-${count.index}"
  region       = var.region
  address_type = "INTERNAL"
  subnetwork   = "projects/${local.vpc_project_id}/regions/${var.region}/subnetworks/${var.runner_subnet_name}"
  labels       = local.runner_labels
}

resource "google_dns_managed_zone" "internal_runner" {
  count = var.restrict_ingress ? 1 : 0

  project     = var.project_id
  name        = "${var.runner_name}-internal"
  dns_name    = "ona-${var.runner_id}.internal."
  description = "Private DNS for the Ona runner"
  visibility  = "private"
  labels      = local.runner_labels

  private_visibility_config {
    networks {
      network_url = "https://www.googleapis.com/compute/v1/projects/${local.vpc_project_id}/global/networks/${var.vpc_name}"
    }
  }
}

resource "google_dns_record_set" "internal_runner" {
  count = var.restrict_ingress ? 1 : 0

  project      = var.project_id
  managed_zone = google_dns_managed_zone.internal_runner[0].name
  name         = "runner.${google_dns_managed_zone.internal_runner[0].dns_name}"
  type         = "A"
  ttl          = 10
  rrdatas      = google_compute_address.internal_runner[*].address
}
