variable "project_id" {
  description = "GCP project ID where runner resources are created."
  type        = string
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

variable "region" {
  description = "GCP region where runner resources are created."
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

variable "vpc_name" {
  description = "Name of the VPC that hosts the runner."
  type        = string
}

variable "vpc_project_id" {
  description = "Project ID that owns the VPC. Defaults to project_id."
  type        = string
  default     = ""
}

variable "runner_subnet_name" {
  description = "Name of the subnet that hosts runners and environments."
  type        = string
}

variable "api_endpoint" {
  description = "Ona management-plane API endpoint."
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
  description = "HTTP, HTTPS, and SOCKS proxy configuration for runner and environment VMs."
  type = object({
    http_proxy  = string
    https_proxy = string
    no_proxy    = string
    all_proxy   = string
  })
  default = null
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

variable "labels" {
  description = "Labels applied to supported GCP resources."
  type        = map(string)
  default     = {}
}
