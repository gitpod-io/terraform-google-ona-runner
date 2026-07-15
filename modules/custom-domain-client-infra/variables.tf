# Customer GCP Project Configuration
variable "project_id" {
  description = "GCP project ID where the client infrastructure will be deployed"
  type        = string
}

variable "region" {
  description = "GCP region for the load balancer and PSC endpoint"
  type        = string
}

# Network Configuration
variable "vpc_network" {
  description = "VPC network name"
  type        = string
  default     = "default"
}

variable "subnet_name" {
  description = "Subnet name for the load balancer"
  type        = string
  default     = "default"
}

# Domain and SSL Configuration
variable "domain_name" {
  description = "Custom domain name for the Ona instance (e.g., gitpod.example.com)"
  type        = string
}

variable "certificate_manager_cert_id" {
  description = "Full resource ID of the Certificate Manager certificate (e.g., projects/PROJECT_ID/locations/REGION/certificates/CERT_NAME)"
  type        = string
}

# Optional Configuration
variable "service_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "gitpod-custom-domain"
}

variable "load_balancer_type" {
  description = "Type of load balancer: 'internal' for private (INTERNAL_MANAGED) or 'external' for public (EXTERNAL_MANAGED)"
  type        = string
  default     = "internal"

  validation {
    condition     = contains(["internal", "external"], var.load_balancer_type)
    error_message = "load_balancer_type must be either 'internal' or 'external'."
  }
}
