data "google_compute_network" "vpc" {
  project = var.project_id
  name    = var.vpc_network
}

data "google_compute_subnetwork" "psc" {
  for_each = var.service_attachments

  project = var.project_id
  name    = each.value.subnet_name
  region  = each.key
}

resource "google_compute_region_network_endpoint_group" "psc" {
  for_each = var.service_attachments

  project               = var.project_id
  name                  = "${var.service_name}-${each.key}-psc-neg"
  region                = each.key
  network               = data.google_compute_network.vpc.id
  subnetwork            = data.google_compute_subnetwork.psc[each.key].id
  network_endpoint_type = "PRIVATE_SERVICE_CONNECT"
  psc_target_service    = each.value.service_attachment_uri
}
