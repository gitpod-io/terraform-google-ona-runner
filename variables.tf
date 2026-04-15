variable "runner_id" {
  description = "The ID of the runner (from Ona dashboard)"
  type        = string
}

variable "project_id" {
  description = "The ID of the GCP project where resources will be created"
  type        = string
}

variable "labels" {
  description = "Labels to apply to GCP resources"
  type        = map(string)
  default     = {}
}

variable "runner_name" {
  description = "The name of the runner"
  type        = string
}

variable "runner_domain" {
  description = "The domain name of the runner"
  type        = string
}

variable "runner_token" {
  description = "The runner token (from Ona dashboard)"
  type        = string
  sensitive   = true
}

variable "vpc_name" {
  description = "The name of the VPC"
  type        = string
  default     = "default"
}

variable "vpc_project_id" {
  description = "The project ID where the VPC is located. Required for Shared VPC setups where the VPC is in a different project. Defaults to project_id if not specified."
  type        = string
  default     = ""
}

variable "runner_subnet_name" {
  description = "The name of the runner subnet"
  type        = string
  default     = "default"
}

variable "region" {
  description = "The region to deploy the resources"
  type        = string
}

variable "runner_vm_config" {
  description = "The configuration for the runner"
  type = object({
    machine_type = string

    update_policy_config = object({
      minimal_action     = string # Use REPLACE for zero-downtime with max_unavailable=0
      surge_percentage   = number # Conservative 25% for runner
      max_unavailable    = number
      replacement_method = string
    })
  })

  default = {
    machine_type = "c4-standard-4"
    update_policy_config = {
      minimal_action     = "REPLACE"
      surge_percentage   = 25
      max_unavailable    = 0
      replacement_method = "SUBSTITUTE"
    }
  }
}

variable "proxy_vm_config" {
  description = "VM proxy configuration for development environment access (required)"
  type = object({
    machine_type = string

    min_instances = number
    max_instances = number

    # Connection draining configuration
    connection_draining_timeout_sec = number # up to 1 hour for graceful shutdown (GCP limit)

    update_policy_config = object({
      minimal_action     = string # Use REPLACE for zero-downtime with max_unavailable=0
      surge_percentage   = number # Aggressive 50% for proxy availability
      max_unavailable    = number
      replacement_method = string
    })

  })
  default = {
    machine_type                    = "c4-standard-2"
    min_instances                   = 2
    max_instances                   = 5
    connection_draining_timeout_sec = 300 # Reduced from 3600 (1 hour) to 5 minutes for faster instance deletion
    update_policy_config = {
      minimal_action     = "REPLACE"
      surge_percentage   = 50
      max_unavailable    = 0
      replacement_method = "SUBSTITUTE"
    }
  }
}

variable "development_version" {
  description = "The development version to use"
  type        = string
  default     = ""
}

variable "api_endpoint" {
  description = "Ona management plane API endpoint"
  type        = string
  default     = "https://app.gitpod.io/api"
}

variable "ssh_port" {
  description = "The SSH port"
  type        = number
  default     = 29222
}

variable "zones" {
  description = "The zones to deploy the resources"
  type        = list(string)
}

variable "certificate_id" {
  description = "The ID of the certificate from Certificate Manager (for external LB)"
  type        = string
  default     = ""

  validation {
    condition     = var.certificate_id == "" || can(regex("^projects/[^/]+/locations/[^/]+/certificates/[^/]+$", var.certificate_id))
    error_message = "The certificate_id must be in the format projects/{project}/locations/{location}/certificates/{name}. For example, projects/my-project/locations/global/certificates/my-cert."
  }
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

variable "certificate_secret_read" {
  description = "Whether to read the certificate secret version at apply time and include it in the trust bundle. Set to false when the secret may not have a version yet (e.g. certbot-managed certificates that are issued asynchronously)."
  type        = bool
  default     = true
}

variable "redis_config" {
  description = "Redis Cluster configuration (cost-optimized defaults: 3 shards, no replicas, small nodes)"
  type = object({
    # Redis Cluster specific settings (minimum viable cluster for cost optimization)
    shard_count   = optional(number, 3)                      # Minimum for cluster: 3 shards
    replica_count = optional(number, 1)                      # High availability with replicas
    node_type     = optional(string, "REDIS_STANDARD_SMALL") # Cost-optimized: small nodes

    # For production with high availability, override with:
    # replica_count = 1 or 2
    # node_type = "REDIS_HIGHMEM_MEDIUM" or "REDIS_HIGHMEM_XLARGE"

    # PSC Connection Policy settings
    psc_connection_limit = optional(number, 10)

    # Performance and lifecycle settings
    custom_configs = optional(map(string), {})
  })

  default = {
    shard_count          = 3
    replica_count        = 1
    node_type            = "REDIS_STANDARD_SMALL"
    psc_connection_limit = 10
    custom_configs       = {}
  }

  validation {
    condition     = var.redis_config.shard_count >= 3 && var.redis_config.shard_count <= 90
    error_message = "Redis Cluster shard_count must be between 3 and 90."
  }

  validation {
    condition     = var.redis_config.replica_count >= 0 && var.redis_config.replica_count <= 5
    error_message = "Redis Cluster replica_count must be between 0 and 5."
  }

  validation {
    condition = contains([
      "REDIS_SHARED_CORE_NANO", "REDIS_HIGHMEM_MEDIUM", "REDIS_HIGHMEM_XLARGE", "REDIS_STANDARD_SMALL"
    ], var.redis_config.node_type)
    error_message = "Redis Cluster node_type must be one of: REDIS_SHARED_CORE_NANO, REDIS_HIGHMEM_MEDIUM, REDIS_HIGHMEM_XLARGE, REDIS_STANDARD_SMALL."
  }
}

# Service port configuration for firewall rules
variable "service_ports" {
  description = "Service ports used by runner and proxy components"
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
  description = "Custom CA certificate configuration that Ona should trust"
  type = object({
    # Either provide file_path OR content, not both
    file_path = optional(string, "") # Path to CA certificate file
    content   = optional(string, "") # Direct CA certificate content
  })
  default = null
}

variable "loadbalancer_type" {
  description = "Type of load balancer to create (external or internal)"
  type        = string
  default     = "external"

  validation {
    condition     = contains(["external", "internal"], var.loadbalancer_type)
    error_message = "The loadbalancer_type must be either 'external' or 'internal'."
  }
}

variable "routable_subnet_name" {
  description = "Subnet for internal load balancer IP allocation (required when loadbalancer_type is internal)"
  type        = string
  default     = ""
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

variable "pre_created_service_accounts" {
  description = "Pre-created service accounts to use instead of creating new ones. If provided, all IAM resources become optional."
  type = object({
    runner         = optional(string, "")
    environment_vm = optional(string, "")
    proxy_vm       = optional(string, "")

    # Deprecated: values are ignored. Kept for backward compatibility.
    build_cache      = optional(string, "")
    secret_manager   = optional(string, "")
    pubsub_processor = optional(string, "")
  })
  default = {
    runner         = ""
    environment_vm = ""
    proxy_vm       = ""
  }

  validation {
    condition = alltrue([
      for k, sa in var.pre_created_service_accounts :
      sa == "" || contains(["build_cache", "secret_manager", "pubsub_processor"], k) || can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]@[a-z0-9-]+\\.iam\\.gserviceaccount\\.com$", sa))
    ])
    error_message = "Service account emails must be in the format: name@project.iam.gserviceaccount.com"
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

variable "mig_warm_pool_enabled" {
  description = "Enable warm pool support using GCP Managed Instance Groups (MIGs) for faster environment startup"
  type        = bool
  default     = false
}
