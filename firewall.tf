
# Firewall rules for proper environment isolation
# These rules are created after proxy deployment to avoid circular dependencies

# Firewall rule for proxy to environments communication
resource "google_compute_firewall" "allow_proxy_to_environments" {
  name    = "${var.runner_name}-allow-proxy-to-environments"
  network = var.vpc_name
  project = local.vpc_project_id

  description = "Allow proxy to communicate with environments on any port"

  allow {
    protocol = "tcp"
    ports    = ["1-65535"]
  }

  allow {
    protocol = "icmp"
  }

  # Use tags for both source and target for consistency
  source_tags = ["gitpod-proxy"]
  target_tags = ["gitpod-type-environment"]

  # depends on proxy vm
  depends_on = [google_compute_backend_service.proxy]
}

# Firewall rule for runner to environments communication
resource "google_compute_firewall" "allow_runner_to_environments" {
  name    = "${var.runner_name}-allow-runner-to-environments"
  network = var.vpc_name
  project = local.vpc_project_id

  description = "Allow runner to communicate with environments on SSH and management ports"

  allow {
    protocol = "tcp"
    ports    = ["22", "22999", "22222", "61000", tostring(var.ssh_port)]
  }

  allow {
    protocol = "icmp"
  }

  source_tags = ["gitpod-runner"]
  target_tags = ["gitpod-type-environment"]

  # depends on proxy vm
  depends_on = [google_compute_backend_service.proxy]
}

# Firewall rule for proxy to access runner backend service
resource "google_compute_firewall" "allow_proxy_to_runner_backend" {
  name    = "${var.runner_name}-allow-proxy-to-runner-backend"
  network = var.vpc_name
  project = local.vpc_project_id

  description = "Allow proxy to access runner backend service on HTTP port and auth-proxy on port 4430"

  allow {
    protocol = "tcp"
    ports    = [tostring(var.service_ports.runner_http_port), "4430", "7070"]
  }

  source_tags = ["gitpod-proxy"]
  target_tags = ["gitpod-runner"]

  # depends on proxy vm
  depends_on = [google_compute_backend_service.proxy]
}

# Deny environments access to runner and proxy services
resource "google_compute_firewall" "deny_environments_to_services" {
  name    = "${var.runner_name}-deny-env-to-services"
  network = var.vpc_name
  project = local.vpc_project_id

  description = "Deny environments from accessing runner and proxy services"

  deny {
    protocol = "tcp"
    ports = [
      tostring(var.service_ports.runner_http_port),
      tostring(var.service_ports.runner_health_port),
      tostring(var.service_ports.proxy_https_port),
      tostring(var.service_ports.proxy_http_port),
      "4430",
      "7070"
    ]
  }

  deny {
    protocol = "icmp"
  }

  source_tags = ["gitpod-type-environment"]
  target_tags = ["gitpod-runner", "gitpod-proxy"]
  priority    = 1000 # Higher priority than allow rules

  # depends on proxy vm
  depends_on = [google_compute_backend_service.proxy]
}

# Firewall rule to allow IAP TCP forwarding to environments on port 22222
resource "google_compute_firewall" "allow_iap_to_environments" {
  name    = "${var.runner_name}-allow-iap-to-environments"
  network = var.vpc_name
  project = local.vpc_project_id

  description = "Allow IAP TCP forwarding IP range (35.235.240.0/20) to access environments on port 22222"

  allow {
    protocol = "tcp"
    ports    = ["22222"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["gitpod-type-environment"]

  # depends on proxy vm
  depends_on = [google_compute_backend_service.proxy]
}

# Firewall rule to allow Network Load Balancer health checks
resource "google_compute_firewall" "allow_network_lb_health_checks" {
  name    = "${var.runner_name}-allow-network-lb-health-checks"
  network = var.vpc_name
  project = local.vpc_project_id

  description = "Allow Network Load Balancer health checks"

  allow {
    protocol = "tcp"
  }

  source_ranges = [
    "35.191.0.0/16",
    "209.85.152.0/22",
    "209.85.204.0/22"
  ]
  target_tags = ["allow-health-check"]

  # depends on proxy vm
  depends_on = [google_compute_backend_service.proxy]
}

# Firewall rule to block outbound email traffic from environments
resource "google_compute_firewall" "deny_email_from_environments" {
  name    = "${var.runner_name}-egress-deny-email"
  network = var.vpc_name
  project = local.vpc_project_id

  description = "Block outbound email traffic from environments"
  direction   = "EGRESS"
  priority    = 1000

  deny {
    protocol = "tcp"
    ports    = ["25", "465", "587"]
  }

  destination_ranges = ["0.0.0.0/0"]
  target_tags        = ["gitpod-type-environment"]

  # depends on proxy vm
  depends_on = [google_compute_backend_service.proxy]
}

# Firewall rule to allow health check traffic
resource "google_compute_firewall" "runner_health_check" {
  name    = "${var.runner_name}-health-check"
  network = var.vpc_name
  project = local.vpc_project_id

  description = "Allow GCP health check traffic to runner instances"

  allow {
    protocol = "tcp"
    ports    = ["9091"]
  }

  # Comprehensive GCP health check source ranges for Load Balancers and Autohealing
  # Sources:
  # - https://cloud.google.com/load-balancing/docs/health-check-concepts#ip-ranges
  # - https://cloud.google.com/compute/docs/instance-groups/autohealing-instances-in-migs
  # These ranges are used by Load Balancers and Managed Instance Group autohealing
  source_ranges = [
    "35.191.0.0/16",   # Primary health check range
    "130.211.0.0/22",  # Legacy health check range
    "209.85.152.0/22", # Network Load Balancer health checks
    "209.85.204.0/22"  # Additional Network Load Balancer health checks
  ]
  target_tags = ["allow-health-check", "lb-health-check"]
}

# Firewall rule to allow internal traffic
resource "google_compute_firewall" "runner_internal_traffic" {
  name    = "${var.runner_name}-internal-traffic"
  network = var.vpc_name
  project = local.vpc_project_id

  description = "Allow internal traffic to runner instances"

  allow {
    protocol = "tcp"
    ports    = ["22", "8080", "9091", "4430"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gitpod-runner"]
}

# Basic firewall rules for SSH and health checks
# Specific proxy and runner communication rules are defined in main.tf after proxy deployment

# Firewall rule for health checks
resource "google_compute_firewall" "allow_health_checks" {
  name    = "${var.runner_name}-allow-health-checks-v2"
  network = var.vpc_name
  project = local.vpc_project_id

  description = "Allow Google Cloud health check ranges for all services"

  allow {
    protocol = "tcp"
    ports    = ["4430", "5000", "8080", "8443", "9091"]
  }

  # Comprehensive Google Cloud health check IP ranges
  # Source: https://cloud.google.com/load-balancing/docs/health-check-concepts#ip-ranges
  source_ranges = [
    "35.191.0.0/16",   # Primary health check range
    "130.211.0.0/22",  # Legacy health check range
    "209.85.152.0/22", # Network Load Balancer health checks
    "209.85.204.0/22"  # Additional Network Load Balancer health checks
  ]
  target_tags = ["gitpod-runner", "gitpod-proxy"]
}

# SSH access to environments is handled by specific proxy and runner rules
# No general SSH access allowed to maintain environment isolation

# VM service communication to environments is handled by specific proxy and runner rules
# This rule is replaced by network tag-based rules in main.tf

# Firewall rule for Google APIs via private endpoints
resource "google_compute_firewall" "allow_google_apis" {
  name    = "${var.runner_name}-allow-google-apis-v2"
  network = var.vpc_name
  project = local.vpc_project_id

  description = "Allow access to Google APIs via private Google access"
  direction   = "EGRESS"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  # Allow access to all Google API ranges for private access
  # This includes metadata server, Cloud APIs, and health check endpoints
  destination_ranges = [
    "199.36.153.8/30",    # restricted.googleapis.com
    "199.36.153.4/30",    # private.googleapis.com
    "169.254.169.254/32", # Metadata server
    "34.96.0.0/14",       # Cloud APIs
    "34.100.0.0/14"       # Additional Cloud APIs
  ]
  target_tags = ["gitpod-runner", "gitpod-proxy"]

  priority = 1000
}

# Firewall rule to allow health check traffic
resource "google_compute_firewall" "proxy_health_check" {
  name    = "${var.runner_name}-proxy-health-check"
  network = var.vpc_name
  project = local.vpc_project_id

  description = "Allow health check traffic to proxy instances"

  allow {
    protocol = "tcp"
    ports    = ["5000", "8080", "8443"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["gitpod-proxy"]
}

# Firewall rule to allow HTTP/HTTPS traffic
resource "google_compute_firewall" "proxy_web_traffic" {
  name    = "${var.runner_name}-proxy-web-traffic"
  network = var.vpc_name
  project = local.vpc_project_id

  description = "Allow HTTP/HTTPS traffic to proxy instances"

  allow {
    protocol = "tcp"
    ports    = ["22", "8080", "8443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gitpod-proxy"]
}

data "google_compute_subnetwork" "runner_subnet" {
  name    = var.runner_subnet_name
  region  = var.region
  project = local.vpc_project_id
}

# Metadata server access - required for IAM token retrieval
resource "google_compute_firewall" "allow_metadata_server" {
  name    = "${var.runner_name}-allow-metadata-server"
  network = var.vpc_name
  project = local.vpc_project_id

  description = "Allow access to GCP metadata server for IAM token retrieval"
  direction   = "EGRESS"
  priority    = 900

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  destination_ranges = ["169.254.169.254/32"]
  target_tags        = ["gitpod-runner", "gitpod-proxy"]
}

# Allow runner to connect to Redis Cluster
# Ports required:
#   - 6379:       Standard Redis client port
#   - 16379:      Cluster bus (gossip protocol for node-to-node communication)
#   - 11000-11099: Shard-specific ports (Memorystore assigns 11000 + shard_id)
resource "google_compute_firewall" "allow_runner_to_redis" {
  name    = "${var.runner_name}-allow-runner-to-redis"
  network = var.vpc_name
  project = local.vpc_project_id

  description = "Allow runner to connect to Redis Cluster via PSC"
  direction   = "EGRESS"
  priority    = 900

  allow {
    protocol = "tcp"
    ports    = ["6379", "16379", "11000-11099"]
  }

  destination_ranges = [data.google_compute_subnetwork.runner_subnet.ip_cidr_range]
  target_tags        = ["gitpod-runner"]
}

# Internal egress rules for runner and proxy communication

# Allow runner egress to proxy for internal coordination
resource "google_compute_firewall" "allow_runner_to_proxy_egress" {
  name    = "${var.runner_name}-allow-runner-to-proxy-egress"
  network = var.vpc_name
  project = local.vpc_project_id

  description = "Allow runner egress to proxy for internal coordination"
  direction   = "EGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = [tostring(var.service_ports.proxy_https_port), tostring(var.service_ports.proxy_http_port)]
  }

  destination_ranges = [data.google_compute_subnetwork.runner_subnet.ip_cidr_range]
  target_tags        = ["gitpod-runner"]
}

# Deny proxy egress to environments on SSH ports (security isolation)
resource "google_compute_firewall" "deny_proxy_to_environments_ssh_egress" {
  name    = "${var.runner_name}-deny-proxy-to-env-ssh-egress"
  network = var.vpc_name
  project = local.vpc_project_id

  description = "Deny proxy egress to environments on SSH ports"
  direction   = "EGRESS"
  priority    = 900

  deny {
    protocol = "tcp"
    ports    = ["22", "22222"]
  }

  destination_ranges = [data.google_compute_subnetwork.runner_subnet.ip_cidr_range]
  target_tags        = ["gitpod-proxy"]
}

# Allow proxy egress to environments on application ports only
resource "google_compute_firewall" "allow_proxy_to_environments_egress" {
  name    = "${var.runner_name}-allow-proxy-to-environments-egress"
  network = var.vpc_name
  project = local.vpc_project_id

  description = "Allow proxy egress to environments on application ports (3000-65535)"
  direction   = "EGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["3000-65535"]
  }

  allow {
    protocol = "icmp"
  }

  destination_ranges = [data.google_compute_subnetwork.runner_subnet.ip_cidr_range]
  target_tags        = ["gitpod-proxy"]
}

# Allow runner egress to environments on SSH and management ports
resource "google_compute_firewall" "allow_runner_to_environments_egress" {
  name    = "${var.runner_name}-allow-runner-to-environments-egress"
  network = var.vpc_name
  project = local.vpc_project_id

  description = "Allow runner egress to environments on SSH and management ports"
  direction   = "EGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["22", "22999", "22222", "61000", tostring(var.ssh_port)]
  }

  allow {
    protocol = "icmp"
  }

  destination_ranges = [data.google_compute_subnetwork.runner_subnet.ip_cidr_range]
  target_tags        = ["gitpod-runner"]
}

# Allow environments to access outside the network (egress)
#
# UDP egress is intentionally restricted to a small set of ports rather than
# wide open. This blocks arbitrary UDP-based data exfiltration and reflection
# /amplification vectors while preserving the developer workflows that
# legitimately need UDP:
#   - 53  (DNS)  - name resolution for apt, git, npm, docker pull, etc.
#   - 123 (NTP)  - clock sync; required for TLS, JWT, git-over-HTTPS
#   - 443 (QUIC) - HTTP/3 to Google, Cloudflare, GitHub, registries, ...
resource "google_compute_firewall" "allow_environments_internet_egress" {
  name    = "${var.runner_name}-allow-env-internet-egress"
  network = var.vpc_name
  project = local.vpc_project_id

  description = "Allow environments to access outside the network (UDP restricted to DNS/NTP/QUIC)"
  direction   = "EGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
    ports    = ["53", "123", "443"]
  }

  allow {
    protocol = "icmp"
  }

  destination_ranges = ["0.0.0.0/0"]
  target_tags        = ["gitpod-type-environment"]
}
