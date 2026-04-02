# Data sources for existing network resources
data "google_compute_network" "vpc" {
  name = var.vpc_network
}

data "google_compute_subnetwork" "subnet" {
  name   = var.subnet_name
  region = var.region
}

# Local variables
locals {
  service_name = var.service_name
  labels = {
    app       = "gitpod"
    component = "custom-domain-client"
  }
  # Ona PSC service attachment URI for production
  gitpod_service_attachment_uri = "https://www.googleapis.com/compute/v1/projects/gitpod-next-production/regions/us-central1/serviceAttachments/gitpod-custom-domain-relay-gcp-psc"
}

# Reserve internal IP address for PSC endpoint
resource "google_compute_address" "psc_ip" {
  name         = "${local.service_name}-psc-ip"
  address_type = "INTERNAL"
  subnetwork   = data.google_compute_subnetwork.subnet.id
  region       = var.region
}

# Create PSC endpoint (forwarding rule) to connect to Ona service attachment
resource "google_compute_forwarding_rule" "psc_endpoint" {
  name    = "${local.service_name}-psc"
  region  = var.region
  network = var.vpc_network

  ip_address = google_compute_address.psc_ip.id
  target     = local.gitpod_service_attachment_uri

  load_balancing_scheme = ""
}

# Create Network Endpoint Group (NEG) for the PSC endpoint
resource "google_compute_region_network_endpoint_group" "psc_neg" {
  name                  = "${local.service_name}-psc-neg"
  region                = var.region
  network               = data.google_compute_network.vpc.id
  subnetwork            = data.google_compute_subnetwork.subnet.id
  network_endpoint_type = "PRIVATE_SERVICE_CONNECT"
  psc_target_service    = local.gitpod_service_attachment_uri
}
