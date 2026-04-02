# Ona Runner Proxy Architecture

## Overview

The Ona Runner Proxy provides secure access to development environments by acting as a gateway/gatekeeper between users and their workspaces. Instead of relying on the centralized Ona gateway, this architecture deploys a local proxy with a load balancer frontend, offering better performance, customization, and control.

## Architecture Context

Based on the Enterprise Runner architecture, the proxy serves as a replacement for the gateway component:

```
┌─────────────────┐    ┌──────────────────────────────────────┐
│   Customer      │    │             AWS Account              │
│   Browser       │────┤                                      │
└─────────────────┘    │  ┌──────────────┐   ┌─────────────┐  │
                       │  │ Load Balancer│───│   Proxy     │  │
                       │  │   (Public)   │   │ (Gateway)   │  │
                       │  └──────────────┘   └─────────────┘  │
                       │           │                │         │
                       │  ┌─────────────────┐       │         │
                       │  │   GKE/EKS       │       │         │
                       │  │   Cluster       │───────┘         │
                       │  │                 │                 │
                       │  │ ┌─────────────┐ │                 │
                       │  │ │Environment 1│ │                 │
                       │  │ ┌─────────────┐ │                 │
                       │  │ │Environment 2│ │                 │
                       │  │ ┌─────────────┐ │                 │
                       │  │ │Environment 3│ │                 │
                       │  └─────────────────┘                 │
                       └──────────────────────────────────────┘
```

## Configuration

The proxy domain is configured via the `RunnerProxyDomain` field in the runner configuration:

```go
// Proxy Server configuration (for SCM OAuth redirection)
RunnerProxyDomain string // Optional: Local proxy domain instead of using gateway
```

## Option 1: External Load Balancer with Public Access

### Architecture
- **Load Balancer**: Google Cloud Load Balancer (HTTPS)
- **SSL Certificate**: Google-managed SSL certificate with wildcard domain
- **Access**: Public internet access with authentication
- **DNS**: Cloud DNS records pointing to load balancer IP

### Components

#### 1. Load Balancer Configuration
```hcl
# External Application Load Balancer
resource "google_compute_global_address" "proxy_ip" {
  name = "${var.name_prefix}-proxy-ip"
}

resource "google_compute_managed_ssl_certificate" "proxy_cert" {
  name = "${var.name_prefix}-proxy-cert"

  managed {
    domains = ["*.${var.proxy_domain}"]
  }
}

resource "google_compute_url_map" "proxy_lb" {
  name            = "${var.name_prefix}-proxy-lb"
  default_service = google_compute_backend_service.proxy_backend.id
}

resource "google_compute_target_https_proxy" "proxy_target" {
  name             = "${var.name_prefix}-proxy-target"
  url_map          = google_compute_url_map.proxy_lb.id
  ssl_certificates = [google_compute_managed_ssl_certificate.proxy_cert.id]
}

resource "google_compute_global_forwarding_rule" "proxy_forwarding_rule" {
  name                  = "${var.name_prefix}-proxy-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "443"
  target                = google_compute_target_https_proxy.proxy_target.id
  ip_address            = google_compute_global_address.proxy_ip.id
}
```

#### 2. Proxy Service (Cloud Run)
```hcl
resource "google_cloud_run_v2_service" "proxy" {
  name     = "${var.name_prefix}-proxy"
  location = var.region

  template {
    service_account = google_service_account.proxy_sa.email

    containers {
      image = var.proxy_image_url

      ports {
        container_port = 8080
      }

      env {
        name  = "PROXY_DOMAIN"
        value = var.proxy_domain
      }

      env {
        name  = "RUNNER_ID"
        value = var.runner_id
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}
```

#### 3. Backend Service
```hcl
resource "google_compute_backend_service" "proxy_backend" {
  name                  = "${var.name_prefix}-proxy-backend"
  load_balancing_scheme = "EXTERNAL"
  protocol              = "HTTP"

  backend {
    group = google_compute_region_network_endpoint_group.proxy_neg.id
  }

  health_checks = [google_compute_health_check.proxy_health.id]
}

resource "google_compute_region_network_endpoint_group" "proxy_neg" {
  name                  = "${var.name_prefix}-proxy-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = google_cloud_run_v2_service.proxy.name
  }
}
```

#### 4. DNS Configuration
```hcl
resource "google_dns_managed_zone" "proxy_zone" {
  name     = "${var.name_prefix}-proxy-zone"
  dns_name = "${var.proxy_domain}."
}

resource "google_dns_record_set" "proxy_wildcard" {
  name = "*.${google_dns_managed_zone.proxy_zone.dns_name}"
  type = "A"
  ttl  = 300

  managed_zone = google_dns_managed_zone.proxy_zone.name

  rrdatas = [google_compute_global_address.proxy_ip.address]
}

resource "google_dns_record_set" "proxy_root" {
  name = google_dns_managed_zone.proxy_zone.dns_name
  type = "A"
  ttl  = 300

  managed_zone = google_dns_managed_zone.proxy_zone.name

  rrdatas = [google_compute_global_address.proxy_ip.address]
}
```

### Pros
- **Simple setup**: Standard Google Cloud Load Balancer
- **Automatic SSL management**: Google-managed certificates
- **Global accessibility**: Can be accessed from anywhere
- **Auto-scaling**: Cloud Run handles scaling automatically

### Cons
- **Public exposure**: Load balancer has public IP
- **Cost**: Higher cost due to global load balancer
- **Security**: Requires additional authentication layers

## Option 2: Internal Load Balancer with Private Access

### Architecture
- **Load Balancer**: Internal Application Load Balancer
- **SSL Certificate**: Google-managed certificate (requires DNS delegation)
- **Access**: Private network access only
- **DNS**: Customer DNS delegation to Google Cloud DNS

### Components

#### 1. Internal Load Balancer Configuration
```hcl
# Internal Application Load Balancer
resource "google_compute_address" "proxy_internal_ip" {
  name         = "${var.name_prefix}-proxy-internal-ip"
  subnetwork   = var.subnet_name
  address_type = "INTERNAL"
  region       = var.region
}

resource "google_compute_region_url_map" "proxy_internal_lb" {
  name            = "${var.name_prefix}-proxy-internal-lb"
  region          = var.region
  default_service = google_compute_region_backend_service.proxy_internal_backend.id
}

resource "google_compute_region_target_https_proxy" "proxy_internal_target" {
  name             = "${var.name_prefix}-proxy-internal-target"
  region           = var.region
  url_map          = google_compute_region_url_map.proxy_internal_lb.id
  ssl_certificates = [google_compute_region_ssl_certificate.proxy_internal_cert.id]
}

resource "google_compute_forwarding_rule" "proxy_internal_forwarding_rule" {
  name                  = "${var.name_prefix}-proxy-internal-rule"
  region                = var.region
  ip_protocol           = "TCP"
  load_balancing_scheme = "INTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_region_target_https_proxy.proxy_internal_target.id
  ip_address            = google_compute_address.proxy_internal_ip.id
  network               = var.vpc_name
  subnetwork            = var.subnet_name
}
```

#### 2. Google-Managed SSL Certificate
```hcl
# DNS managed zone for internal domain
resource "google_dns_managed_zone" "proxy_internal_zone" {
  name        = "${var.name_prefix}-proxy-internal-zone"
  dns_name    = "${var.proxy_domain}."
  description = "Internal DNS zone for proxy domain"

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = var.vpc_id
    }
  }
}

# Google-managed SSL certificate for internal use
resource "google_compute_region_ssl_certificate" "proxy_internal_cert" {
  name_prefix = "${var.name_prefix}-proxy-internal-cert-"
  region      = var.region

  managed {
    domains = ["*.${var.proxy_domain}"]
  }

  lifecycle {
    create_before_destroy = true
  }
}
```

#### 3. DNS Records for Internal Access
```hcl
# Internal DNS records
resource "google_dns_record_set" "proxy_internal_wildcard" {
  name = "*.${google_dns_managed_zone.proxy_internal_zone.dns_name}"
  type = "A"
  ttl  = 300

  managed_zone = google_dns_managed_zone.proxy_internal_zone.name

  rrdatas = [google_compute_address.proxy_internal_ip.address]
}

resource "google_dns_record_set" "proxy_internal_root" {
  name = google_dns_managed_zone.proxy_internal_zone.dns_name
  type = "A"
  ttl  = 300

  managed_zone = google_dns_managed_zone.proxy_internal_zone.name

  rrdatas = [google_compute_address.proxy_internal_ip.address]
}
```

#### 4. Internal Backend Service
```hcl
resource "google_compute_region_backend_service" "proxy_internal_backend" {
  name                  = "${var.name_prefix}-proxy-internal-backend"
  region                = var.region
  load_balancing_scheme = "INTERNAL_MANAGED"
  protocol              = "HTTP"

  backend {
    group = google_compute_region_network_endpoint_group.proxy_internal_neg.id
  }

  health_checks = [google_compute_region_health_check.proxy_internal_health.id]
}

resource "google_compute_region_network_endpoint_group" "proxy_internal_neg" {
  name                  = "${var.name_prefix}-proxy-internal-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = google_cloud_run_v2_service.proxy.name
  }
}
```


### Pros
- **Enhanced security**: No public internet exposure
- **Lower cost**: Regional load balancer costs less
- **Network isolation**: Stays within private network
- **Compliance**: Better for regulated industries
- **Managed certificates**: Google-managed SSL certificates

### Cons
- **DNS requirements**: Requires DNS delegation for certificate validation
- **Limited accessibility**: Only from within VPC or connected networks
- **Setup complexity**: More complex than external load balancer


## Terraform Implementation Plan

### Module Structure
```
modules/
├── proxy-external/     # Option 1: External Load Balancer
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── versions.tf
└── proxy-internal/     # Option 2: Internal Load Balancer
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── versions.tf
```

### Variables Configuration
```hcl
variable "proxy_config" {
  description = "Proxy configuration"
  type = object({
    enabled = bool
    type    = string # "external", "internal"
    domain  = string

    # Optional configurations
    image_url           = optional(string)

    # DNS configuration
    dns_zone_name       = optional(string)
  })
  default = {
    enabled = false
    type    = "external"
    domain  = ""
  }
}
```

### Integration with Main Module
```hcl
# In main.tf
module "proxy" {
  count  = var.proxy_config.enabled ? 1 : 0
  source = "./modules/proxy-${var.proxy_config.type}"

  project_id   = var.project_id
  region       = var.region
  name_prefix  = local.name_prefix
  labels       = local.common_labels

  # Networking
  vpc_name     = local.vpc_name
  subnet_name  = local.subnet_name
  subnet_cidr  = var.vpc_config.subnet_cidr

  # Proxy configuration
  proxy_domain = var.proxy_config.domain
  proxy_config = var.proxy_config

  # Service account
  service_account_email = module.security.proxy_service_account_email

  depends_on = [module.services]
}
```

### Output Configuration
```hcl
# Proxy outputs
output "proxy_configuration" {
  description = "Proxy configuration details"
  value = var.proxy_config.enabled ? {
    enabled           = true
    type             = var.proxy_config.type
    domain           = var.proxy_config.domain
    load_balancer_ip = try(module.proxy[0].load_balancer_ip, null)
    service_url      = try(module.proxy[0].service_url, null)
    dns_records      = try(module.proxy[0].dns_records, [])
    ssl_certificate  = try(module.proxy[0].ssl_certificate_info, null)
  } : null
}
```

## Security Considerations

### Authentication & Authorization
- **OAuth Integration**: Support for SCM OAuth flows
- **JWT Validation**: Verify tokens from Ona management plane
- **RBAC**: Role-based access control for environments
- **Audit Logging**: Log all access attempts and proxy actions

### Network Security
- **IP Allowlisting**: Restrict access to known IP ranges
- **Rate Limiting**: Prevent abuse and DDoS attacks
- **Header Validation**: Validate and sanitize HTTP headers
- **TLS Configuration**: Strong TLS cipher suites and protocols

### Certificate Management
- **Automatic Renewal**: Automated certificate renewal process
- **Certificate Monitoring**: Alert on certificate expiration
- **Key Rotation**: Regular rotation of private keys
- **Certificate Pinning**: Optional certificate pinning for enhanced security

## Deployment Considerations

### Prerequisites
1. **Domain Ownership**: Customer must own the proxy domain
2. **DNS Management**: Access to configure DNS records or delegate DNS to Google Cloud
3. **Network Planning**: VPC connectivity for internal option (VPN, Interconnect, or peering)

### Migration Strategy
1. **Parallel Deployment**: Deploy proxy alongside existing gateway
2. **Gradual Cutover**: Route traffic incrementally to proxy
3. **Rollback Plan**: Quick rollback to gateway if issues occur
4. **Monitoring**: Comprehensive monitoring during migration

### Operational Requirements
- **Health Checks**: Automated health monitoring
- **Certificate Management**: Automated certificate renewal via Google-managed certificates
- **Scaling**: Automatic scaling based on demand
- **Updates**: Rolling updates for proxy service

## Summary

This architecture provides two robust options for proxy deployment:

1. **External Load Balancer**: Best for general use cases with public internet access
2. **Internal Load Balancer**: Best for enterprise environments requiring private network access

Both options use Google-managed SSL certificates and integrate seamlessly with the existing Ona runner infrastructure, providing a secure and scalable gateway for development environment access.

## Cost Estimation

### Assumptions
- **Usage**: 12 hours per day (50% daily utilization)
- **Data Transfer**: 1TB per month total
- **Region**: us-central1 (Iowa)
- **Currency**: USD
- **Pricing**: Based on Google Cloud pricing as of 2024

### Option 1: External Load Balancer Cost Breakdown

| Component | Specification | Monthly Cost |
|-----------|---------------|--------------|
| **Global External Application Load Balancer** | | |
| - Forwarding rules | 1 rule × $18/month | $18.00 |
| - Processing charges | 1TB × $0.008/GB | $8.00 |
| **Cloud Run (Proxy Service)** | | |
| - CPU allocation | 1 vCPU × 12h/day × 30 days × $0.00002400/vCPU-sec | $31.10 |
| - Memory allocation | 2GB × 12h/day × 30 days × $0.00000250/GB-sec | $6.48 |
| - Requests | 1M requests × $0.40/1M requests | $0.40 |
| **Google-Managed SSL Certificate** | Wildcard certificate | $0.00 |
| **Cloud DNS** | | |
| - Hosted zone | 1 zone × $0.20/month | $0.20 |
| - DNS queries | 1M queries × $0.40/1M queries | $0.40 |
| **Egress Traffic** | | |
| - Internet egress | 1TB × $0.12/GB (>1GB tier) | $120.00 |
| **Network Endpoint Group** | Regional NEG | $0.00 |
| | **Total Monthly Cost** | **$184.58** |

### Option 2: Internal Load Balancer Cost Breakdown

| Component | Specification | Monthly Cost |
|-----------|---------------|--------------|
| **Internal Application Load Balancer** | | |
| - Forwarding rules | 1 rule × $18/month | $18.00 |
| - Processing charges | 1TB × $0.008/GB | $8.00 |
| **Cloud Run (Proxy Service)** | | |
| - CPU allocation | 1 vCPU × 12h/day × 30 days × $0.00002400/vCPU-sec | $31.10 |
| - Memory allocation | 2GB × 12h/day × 30 days × $0.00000250/GB-sec | $6.48 |
| - Requests | 1M requests × $0.40/1M requests | $0.40 |
| **Google-Managed SSL Certificate** | Wildcard certificate (regional) | $0.00 |
| **Private Cloud DNS** | | |
| - Private hosted zone | 1 zone × $0.20/month | $0.20 |
| - DNS queries | 1M queries × $0.40/1M queries | $0.40 |
| **Internal Traffic** | | |
| - VPC internal traffic | 1TB × $0.01/GB | $10.00 |
| **Network Endpoint Group** | Regional NEG | $0.00 |
| | **Total Monthly Cost** | **$74.58** |

### Cost Comparison Summary

| Option | Monthly Cost | Annual Cost | Key Cost Drivers |
|--------|--------------|-------------|------------------|
| **External Load Balancer** | $184.58 | $2,215.00 | Internet egress ($120), LB processing ($26) |
| **Internal Load Balancer** | $74.58 | $895.00 | Internal traffic ($10), LB processing ($26) |
| **Cost Difference** | $110.00 | $1,320.00 | 60% savings with internal option |

### Cost Optimization Opportunities

#### For External Load Balancer:
1. **CDN Integration**: Use Cloud CDN to reduce egress costs
   - Potential savings: $60-80/month on static content
2. **Committed Use Discounts**: 1-year commitment for predictable workloads
   - Potential savings: 20-25% on compute costs
3. **Regional External Load Balancer**: If global access not needed
   - Potential savings: $8-10/month on processing

#### For Internal Load Balancer:
1. **VPC Peering**: Optimize network architecture
   - Potential savings: $2-3/month on internal traffic
2. **Resource Right-sizing**: Adjust Cloud Run CPU/memory based on actual usage
   - Potential savings: $10-15/month if over-provisioned

### Scaling Cost Projections

#### Data Transfer Scaling (Internal LB):
| Monthly Data | Processing Cost | Internal Traffic | Total Additional |
|--------------|-----------------|------------------|------------------|
| 2TB | $16.00 | $20.00 | $36.00 |
| 5TB | $40.00 | $50.00 | $90.00 |
| 10TB | $80.00 | $100.00 | $180.00 |

#### Usage Scaling (both options):
| Daily Hours | CPU Cost | Memory Cost | Total Compute |
|-------------|----------|-------------|---------------|
| 6h (25%) | $15.55 | $3.24 | $18.79 |
| 12h (50%) | $31.10 | $6.48 | $37.58 |
| 24h (100%) | $62.20 | $12.96 | $75.16 |

### Key Cost Insights

1. **Internal is 60% cheaper**: Primarily due to lower network egress costs
2. **Network costs dominate**: 65% of external LB costs are network-related
3. **Compute costs are consistent**: Same Cloud Run costs for both options
4. **Load balancer overhead**: ~$26/month baseline for either option
5. **Break-even point**: Internal option pays for itself after 1 month

### Cost Monitoring Recommendations

1. **Set up billing alerts** at $50, $100, and $150 monthly thresholds
2. **Monitor network egress** usage patterns for optimization opportunities
3. **Track Cloud Run metrics** to right-size CPU and memory allocation
4. **Review DNS query patterns** to optimize caching strategies
5. **Consider regional vs global** load balancer based on user geography

*Note: Prices are estimates based on Google Cloud pricing and may vary based on actual usage patterns, regional availability, and pricing changes.*
