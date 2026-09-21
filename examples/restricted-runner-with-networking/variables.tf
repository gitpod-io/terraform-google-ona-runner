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

variable "development_version" {
  description = "Development version used to select runner component images."
  type        = string
  default     = ""
}

variable "ssh_port" {
  description = "SSH port used for environment access."
  type        = number
  default     = 29222
}

variable "service_ports" {
  description = "Service ports used by runner components. Proxy ports are retained for root-module compatibility but are unused in restricted mode."
  type = object({
    runner_http_port   = number
    runner_health_port = number
    proxy_https_port   = number
    proxy_http_port    = number
  })
  default = {
    runner_http_port   = 8080
    runner_health_port = 9091
    proxy_https_port   = 8443
    proxy_http_port    = 5000
  }
}

variable "proxy_config" {
  description = "HTTP, HTTPS, and SOCKS proxy configuration for runner and environment VMs. Non-empty proxy URLs must include a hostname or IPv4 address and explicit port."
  type = object({
    http_proxy  = string
    https_proxy = string
    no_proxy    = string
    all_proxy   = string
  })
  default = null

  validation {
    condition = var.proxy_config == null || alltrue([
      for proxy_url in compact([
        var.proxy_config.http_proxy,
        var.proxy_config.https_proxy,
        var.proxy_config.all_proxy,
        ]) : try(
        parseint(regex("^[A-Za-z][A-Za-z0-9+.-]*://([^@/]+@)?([^:/?#]+):([0-9]{1,5})$", proxy_url)[2], 10) >= 1 &&
        parseint(regex("^[A-Za-z][A-Za-z0-9+.-]*://([^@/]+@)?([^:/?#]+):([0-9]{1,5})$", proxy_url)[2], 10) <= 65535,
        false,
      )
    ])
    error_message = "Non-empty proxy URLs must use scheme://hostname-or-ip:port with a port between 1 and 65535."
  }
}

variable "ca_certificate" {
  description = "Custom CA certificate trusted by runner and environment VMs."
  type = object({
    file_path = optional(string, "")
    content   = optional(string, "")
  })
  default = null
}

variable "auth_proxy_cert_rotation_triggers" {
  description = "Values that force rotation of the runner's auth-proxy TLS certificate when changed."
  type        = map(string)
  default     = {}
}

variable "create_cmek" {
  description = "Create and manage a KMS key for CMEK encryption."
  type        = bool
  default     = false
}

variable "kms_key_name" {
  description = "Existing KMS key used for CMEK encryption when create_cmek is false."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_name == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key_name))
    error_message = "kms_key_name must use projects/{project}/locations/{location}/keyRings/{keyring}/cryptoKeys/{key}."
  }
}

variable "pre_created_service_accounts" {
  description = "Pre-created runner and environment VM service accounts. Set attach_iam_policies to true to let the module manage their required IAM."
  type = object({
    runner              = optional(string, "")
    environment_vm      = optional(string, "")
    attach_iam_policies = optional(bool, false)
  })
  default = {
    runner              = ""
    environment_vm      = ""
    attach_iam_policies = false
  }
}

variable "custom_images" {
  description = "Custom runner and sidecar images, with optional registry credentials and insecure-registry configuration."
  type = object({
    runner_image        = optional(string, "")
    prometheus_image    = optional(string, "")
    node_exporter_image = optional(string, "")
    docker_config_json  = optional(string, "")
    insecure            = optional(bool, false)
  })
  default = {
    runner_image        = ""
    prometheus_image    = ""
    node_exporter_image = ""
    docker_config_json  = ""
    insecure            = false
  }

  validation {
    condition     = var.custom_images.docker_config_json == "" || can(jsondecode(var.custom_images.docker_config_json))
    error_message = "docker_config_json must be empty or valid JSON."
  }
}

variable "enable_agents" {
  description = "Enable LLM agent execution in Ona environments."
  type        = bool
  default     = true
}

variable "enable_cross_zone_restart" {
  description = "Enable snapshot fallback when a stopped dual-disk environment cannot restart in its original zone."
  type        = bool
  default     = false
}

variable "use_authoritative_project_metadata" {
  description = "Manage all project metadata authoritatively instead of managing SSH-related keys individually."
  type        = bool
  default     = true
}

variable "internal_runner_endpoint_version" {
  description = "Increase to rotate the internal runner endpoint TLS key and certificate."
  type        = number
  default     = 1

  validation {
    condition     = var.internal_runner_endpoint_version >= 1 && floor(var.internal_runner_endpoint_version) == var.internal_runner_endpoint_version
    error_message = "internal_runner_endpoint_version must be a positive integer."
  }
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
  description = "HTTPS domains allowed through Cloud NGFW. When null, the firewall.yaml baseline is used; an explicit set replaces it. FQDN objects do not support wildcards."
  type        = set(string)
  default     = null

  validation {
    condition = var.firewall_allowed_domains == null ? true : length(var.firewall_allowed_domains) > 0 && alltrue([
      for domain in var.firewall_allowed_domains :
      length(domain) <= 253 && can(regex("^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.)+[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$", domain))
    ])
    error_message = "firewall_allowed_domains must be null or contain one or more exact, valid domain names."
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
