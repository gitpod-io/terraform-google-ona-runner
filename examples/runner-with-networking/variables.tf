# Required Variables

variable "project_id" {
  description = "GCP project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "GCP region for resource deployment"
  type        = string
}

variable "zones" {
  description = "List of GCP zones for distributing zonal resources (required for predictable deployments)"
  type        = list(string)

  validation {
    condition     = length(var.zones) > 0 && length(var.zones) <= 10
    error_message = "Zones must be specified (1-10 zones required for predictable deployments)."
  }
}

variable "runner_name" {
  description = "Name of the runner"
  type        = string
}

variable "runner_id" {
  description = "ID of the runner"
  type        = string
}

variable "runner_token" {
  description = "Ona runner authentication token (join token) - will be stored in Secret Manager"
  type        = string
  sensitive   = true
}

variable "runner_domain" {
  description = "Domain of the runner"
  type        = string
}


# Optional Variables

variable "api_endpoint" {
  description = "Ona management plane API endpoint"
  type        = string
  default     = "https://app.gitpod.io/api"
}

variable "certificate_id" {
  description = "ID of the certificate in GCP resource format: projects/{project}/locations/{location}/certificates/{name}"
  type        = string
  default     = ""

  validation {
    condition     = var.certificate_id == "" || can(regex("^projects/[^/]+/locations/[^/]+/certificates/[^/]+$", var.certificate_id))
    error_message = "The certificate_id must be in the format projects/{project}/locations/{location}/certificates/{name}. For example, projects/my-project/locations/global/certificates/my-cert."
  }
}


variable "ssh_port" {
  description = "SSH port for environment access"
  type        = number
  default     = 29222

  validation {
    condition     = var.ssh_port >= 1024 && var.ssh_port <= 65535
    error_message = "SSH port must be between 1024 and 65535."
  }
}

variable "development_version" {
  description = "Development version for component URLs (sets GITPOD_DEVELOPMENT_VERSION)"
  type        = string
  default     = ""
}

variable "labels" {
  description = "Labels to apply to your Ona resoruces"
  type        = map(string)
  default     = {}
}

variable "proxy_config" {
  description = "HTTP/HTTPS proxy configuration for Docker containers and VMs"
  type = object({
    http_proxy  = string
    https_proxy = string
    no_proxy    = string
    all_proxy   = string
  })
  default = null
}

variable "ca_certificate" {
  description = "Custom CA certificate configuration for proxy and other tools"
  type = object({
    # Either provide file_path OR content, not both
    file_path = optional(string, "") # Path to CA certificate file
    content   = optional(string, "") # Direct CA certificate content
  })
  default = null
}

variable "loadbalancer_type" {
  description = "Type of load balancer to use for the runner"
  type        = string
  default     = "external"
}

variable "certificate_secret_id" {
  description = "The ID of the Secret Manager secret containing certificate and private key (for internal LB)"
  type        = string
  default     = ""

  validation {
    condition     = var.certificate_secret_id == "" || can(regex("^projects/[^/]+/secrets/[^/]+$", var.certificate_secret_id))
    error_message = "The certificate_secret_id must be in the format projects/{project}/secrets/{name}. For example, projects/my-project/secrets/my-cert-secret."
  }
}

variable "enable_certbot" {
  description = "Enable automatic certificate management via Let's Encrypt certbot. Only applicable for internal load balancers."
  type        = bool
  default     = false
}

variable "certbot_email" {
  description = "Email for Let's Encrypt registration. Required when enable_certbot is true."
  type        = string
  default     = ""
}

variable "run_initial_certbot" {
  description = "Trigger the initial certbot certificate issuance during apply. Only set to true after NS delegation is configured for the DNS zone."
  type        = bool
  default     = false
}

variable "runner_size" {
  description = "Runner size profile: 'regular' for production workloads, 'small' for test/dev (cheaper VMs, fewer proxy replicas, nano Redis nodes)"
  type        = string
  default     = "regular"

  validation {
    condition     = contains(["small", "regular"], var.runner_size)
    error_message = "runner_size must be either 'small' or 'regular'."
  }
}

variable "create_cmek" {
  description = "Create KMS keyring and key for CMEK encryption. When true, creates and manages KMS resources automatically."
  type        = bool
  default     = false
}


variable "kms_key_name" {
  description = "The KMS key name for CMEK encryption of GCP resources. Only used when create_cmek = false. Ignored when create_cmek = true."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_name == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key_name))
    error_message = "The kms_key_name must be in the format projects/{project}/locations/{location}/keyRings/{keyring}/cryptoKeys/{key}."
  }
}

variable "custom_images" {
  description = "Custom Docker images to use instead of default ones. Optionally includes Docker config.json content for registry credentials and insecure registry flag."
  type = object({
    runner_image        = optional(string, "")
    proxy_image         = optional(string, "")
    prometheus_image    = optional(string, "")
    node_exporter_image = optional(string, "")
    docker_config_json  = optional(string, "")  # Docker config.json content (JSON string)
    insecure            = optional(bool, false) # Mark custom image registries as insecure
  })
  default = {
    runner_image        = ""
    proxy_image         = ""
    prometheus_image    = ""
    node_exporter_image = ""
    docker_config_json  = ""
    insecure            = false
  }

  validation {
    condition     = var.custom_images.docker_config_json == "" || can(jsondecode(var.custom_images.docker_config_json))
    error_message = "docker_config_json must be empty or valid JSON string."
  }
}

variable "enable_agents" {
  description = "Enable LLM agents execution feature in your Ona environments"
  type        = bool
  default     = true
}

variable "honeycomb_api_key" {
  description = "Honeycomb API key for development tracing. Enables tracing on the runner and environments when set."
  type        = string
  default     = ""
  sensitive   = true
}
