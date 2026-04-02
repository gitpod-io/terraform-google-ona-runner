terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# VPC creation
resource "google_compute_network" "vpc" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
  project                 = var.project_id
}

resource "google_compute_subnetwork" "runner_subnet" {
  name          = "${var.name_prefix}-runner-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id
  project       = var.project_id

  private_ip_google_access = true

  purpose = var.create_private_network ? "PRIVATE" : ""

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_subnetwork" "proxy_subnet" {
  count = var.create_private_network ? 1 : 0

  name          = "${var.name_prefix}-proxy-subnet"
  ip_cidr_range = "100.64.0.0/16"
  region        = var.region
  network       = google_compute_network.vpc.id
  project       = var.project_id

  purpose = "REGIONAL_MANAGED_PROXY"
  role    = "ACTIVE"
}

# Cloud Router for NAT
resource "google_compute_router" "router" {
  name    = "${var.name_prefix}-router"
  region  = var.region
  network = google_compute_network.vpc.id
  project = var.project_id

  bgp {
    asn = 64514
  }
}

# Cloud NAT for outbound internet access
resource "google_compute_router_nat" "nat" {
  name    = "${var.name_prefix}-nat"
  router  = google_compute_router.router.name
  region  = var.region
  project = var.project_id

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  # Enable NAT for VM instances
  endpoint_types = ["ENDPOINT_TYPE_VM", "ENDPOINT_TYPE_SWG"]

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Firewall rule for outbound internet access (required for external API calls)
resource "google_compute_firewall" "allow_outbound_internet" {
  name    = "${var.name_prefix}-allow-outbound-internet"
  network = google_compute_network.vpc.id
  project = var.project_id

  description = "Allow outbound HTTPS traffic for external API calls (like app.gitpod.io)"
  direction   = "EGRESS"

  allow {
    protocol = "tcp"
    ports    = ["443", "80"]
  }

  # Allow outbound traffic to all destinations
  destination_ranges = ["0.0.0.0/0"]
  target_tags        = ["gitpod-runner", "gitpod-proxy", "gitpod-type-environment"]

  priority = 1000
}
