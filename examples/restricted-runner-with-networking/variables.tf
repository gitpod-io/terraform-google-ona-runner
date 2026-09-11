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

variable "labels" {
  description = "Labels applied to supported GCP resources."
  type        = map(string)
  default     = {}
}
