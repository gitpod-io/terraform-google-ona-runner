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

variable "labels" {
  description = "Labels applied to supported GCP resources."
  type        = map(string)
  default     = {}
}
