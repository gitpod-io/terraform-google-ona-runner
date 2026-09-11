variable "project_id" {
  description = "GCP project ID where resources are created."
  type        = string
}

variable "region" {
  description = "GCP region where resources are created."
  type        = string
}

variable "zones" {
  description = "Zones across which the two fixed runner instances are distributed."
  type        = list(string)

  validation {
    condition     = length(var.zones) >= 2 && length(distinct(var.zones)) == length(var.zones)
    error_message = "zones must contain at least two distinct zones."
  }
}

variable "runner_id" {
  description = "Ona runner ID."
  type        = string
}

variable "runner_token" {
  description = "Ona runner exchange token."
  type        = string
  sensitive   = true
}

variable "runner_name" {
  description = "Human-readable runner name used in GCP resource names."
  type        = string
  default     = "ona-runner"
}

variable "api_endpoint" {
  description = "Ona management-plane API endpoint. Add its hostname to firewall_allowed_domains when overriding the default."
  type        = string
  default     = "https://app.gitpod.io/api"
}

variable "subnet_cidr" {
  description = "IPv4 CIDR used by runners and environments."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.subnet_cidr))
    error_message = "subnet_cidr must be a valid IPv4 CIDR."
  }
}

variable "psc_google_apis_ip" {
  description = "Global internal IPv4 address for the Google APIs PSC endpoint. It must be outside every subnet and allocated range in the VPC."
  type        = string
  default     = "10.255.0.5"

  validation {
    condition     = can(cidrnetmask("${var.psc_google_apis_ip}/32"))
    error_message = "psc_google_apis_ip must be a valid IPv4 address."
  }
}

variable "firewall_allowed_domains" {
  description = "HTTPS domains allowed through Cloud NGFW. app.gitpod.io is the only default. FQDN objects do not support wildcards."
  type        = set(string)
  default     = ["app.gitpod.io"]

  validation {
    condition = length(var.firewall_allowed_domains) > 0 && alltrue([
      for domain in var.firewall_allowed_domains :
      length(domain) <= 253 && can(regex("^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.)+[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$", domain))
    ])
    error_message = "firewall_allowed_domains must contain one or more exact, valid domain names."
  }
}

variable "firewall_allowed_ip_ranges" {
  description = "Additional IPv4 CIDRs allowed over HTTPS through Cloud NGFW."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.firewall_allowed_ip_ranges : can(cidrnetmask(cidr))])
    error_message = "firewall_allowed_ip_ranges must contain valid IPv4 CIDRs."
  }
}

variable "security_log_bucket_location" {
  description = "Location for the dedicated security log bucket. Use a location compatible with the deployment's data-residency requirements."
  type        = string
  default     = "global"

  validation {
    condition     = length(trimspace(var.security_log_bucket_location)) > 0
    error_message = "security_log_bucket_location must not be empty."
  }
}

variable "security_log_retention_days" {
  description = "Number of days to retain restricted-runner security logs."
  type        = number
  default     = 90

  validation {
    condition     = var.security_log_retention_days >= 1 && var.security_log_retention_days <= 3650
    error_message = "security_log_retention_days must be between 1 and 3650."
  }
}

variable "lock_security_log_bucket" {
  description = "Permanently lock the security log bucket retention policy. This is irreversible; locked buckets are abandoned rather than deleted during Terraform destroy."
  type        = bool
  default     = false
}

variable "security_log_export_destinations" {
  description = "Additional named Cloud Logging sink destinations for cross-project archives or SIEM streaming. The destination must grant the emitted writer identity permission to write."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for name, destination in var.security_log_export_destinations :
      can(regex("^[a-z][a-z0-9-]{0,40}$", name)) && can(regex("^(logging|storage|bigquery|pubsub)\\.googleapis\\.com/", destination))
    ])
    error_message = "security_log_export_destinations keys must be lowercase names and values must be Cloud Logging, Storage, BigQuery, or Pub/Sub destinations."
  }
}

variable "security_notification_channels" {
  description = "Cloud Monitoring notification channel resource names used by restricted-runner security alerts."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for channel in var.security_notification_channels :
      can(regex("^projects/[^/]+/notificationChannels/[^/]+$", channel))
    ])
    error_message = "security_notification_channels must contain full notification channel resource names."
  }
}

variable "enable_security_alerts" {
  description = "Create Cloud Monitoring policies for denied egress, denied environment API calls, security-control changes, DNS anomalies, and inspection fallback."
  type        = bool
  default     = true
}

variable "dns_nxdomain_alert_threshold" {
  description = "Number of NXDOMAIN responses in five minutes that triggers the DNS anomaly alert."
  type        = number
  default     = 100

  validation {
    condition     = var.dns_nxdomain_alert_threshold >= 1
    error_message = "dns_nxdomain_alert_threshold must be at least 1."
  }
}

variable "enable_extended_audit_logs" {
  description = "Enable Data Access audit logs for Artifact Registry, Cloud Logging, Cloud Monitoring, and Cloud KMS in addition to the runner module's existing audit coverage."
  type        = bool
  default     = true
}

variable "enable_url_filtering" {
  description = "Enable project-scoped Cloud NGFW Enterprise URL filtering for environment HTTPS traffic. This creates a billable firewall endpoint in every configured zone."
  type        = bool
  default     = false
}

variable "url_filtering_tls_inspection_policy" {
  description = "Optional existing TLS inspection policy URL to attach to URL-filtering endpoints. Clients must trust its issuing CA."
  type        = string
  default     = null

  validation {
    condition = (
      var.url_filtering_tls_inspection_policy == null ||
      can(regex("^https://networksecurity\\.googleapis\\.com/v1/(projects|organizations)/[^/]+/locations/${var.region}/tlsInspectionPolicies/[^/]+$", var.url_filtering_tls_inspection_policy))
    )
    error_message = "url_filtering_tls_inspection_policy must be a fully qualified Network Security API TLS inspection policy URL in the runner region."
  }

  validation {
    condition     = var.url_filtering_tls_inspection_policy == null || var.enable_url_filtering
    error_message = "enable_url_filtering must be true when url_filtering_tls_inspection_policy is set."
  }
}

variable "packet_mirroring_collector_forwarding_rule" {
  description = "Optional full URL of a regional INTERNAL forwarding rule configured as a packet-mirroring collector. Environment VM traffic is mirrored when set."
  type        = string
  default     = null

  validation {
    condition = (
      var.packet_mirroring_collector_forwarding_rule == null ||
      can(regex("^https://www\\.googleapis\\.com/compute/v1/projects/[^/]+/regions/${var.region}/forwardingRules/[^/]+$", var.packet_mirroring_collector_forwarding_rule))
    )
    error_message = "packet_mirroring_collector_forwarding_rule must be a full Compute Engine forwarding rule URL in the runner region."
  }
}

variable "labels" {
  description = "Labels applied to supported GCP resources."
  type        = map(string)
  default     = {}
}
