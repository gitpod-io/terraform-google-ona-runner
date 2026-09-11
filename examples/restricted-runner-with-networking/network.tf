resource "google_compute_network" "runner" {
  project                                   = var.project_id
  name                                      = "${local.name_prefix}-vpc"
  auto_create_subnetworks                   = false
  network_firewall_policy_enforcement_order = "BEFORE_CLASSIC_FIREWALL"
  delete_default_routes_on_create           = false
  routing_mode                              = "REGIONAL"

  depends_on = [google_project_service.required]
}

resource "google_compute_subnetwork" "runner" {
  project                  = var.project_id
  name                     = "${local.name_prefix}-subnet"
  region                   = var.region
  network                  = google_compute_network.runner.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 1.0
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_router" "egress" {
  project = var.project_id
  name    = "${local.name_prefix}-router"
  region  = var.region
  network = google_compute_network.runner.id
}

resource "google_compute_router_nat" "egress" {
  project = var.project_id
  name    = "${local.name_prefix}-nat"
  region  = var.region
  router  = google_compute_router.egress.name

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.runner.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ALL"
  }
}

resource "google_compute_global_address" "google_apis" {
  project      = var.project_id
  name         = "${local.name_prefix}-google-apis"
  address_type = "INTERNAL"
  purpose      = "PRIVATE_SERVICE_CONNECT"
  network      = google_compute_network.runner.id
  address      = var.psc_google_apis_ip
}

resource "google_compute_global_forwarding_rule" "google_apis" {
  project               = var.project_id
  name                  = local.psc_endpoint_name
  target                = "all-apis"
  network               = google_compute_network.runner.id
  ip_address            = google_compute_global_address.google_apis.id
  load_balancing_scheme = ""

  depends_on = [google_project_service.required]
}

resource "google_dns_managed_zone" "google_apis" {
  for_each = local.google_api_dns_domains

  project     = var.project_id
  name        = "${local.name_prefix}-${replace(each.value, ".", "-")}"
  dns_name    = "${each.value}."
  description = "Routes ${each.value} to the Google APIs PSC endpoint."
  visibility  = "private"
  labels      = local.common_labels

  private_visibility_config {
    networks {
      network_url = google_compute_network.runner.id
    }
  }

  depends_on = [google_project_service.required]
}

resource "google_dns_record_set" "google_apis" {
  for_each = local.google_api_dns_domains

  project      = var.project_id
  managed_zone = google_dns_managed_zone.google_apis[each.value].name
  name         = "${each.value}."
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.google_apis.address]
}

resource "google_dns_record_set" "google_apis_wildcard" {
  for_each = local.google_api_dns_domains

  project      = var.project_id
  managed_zone = google_dns_managed_zone.google_apis[each.value].name
  name         = "*.${each.value}."
  type         = "CNAME"
  ttl          = 300
  rrdatas      = ["${each.value}."]
}
