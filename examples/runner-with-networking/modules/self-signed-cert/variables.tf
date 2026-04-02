variable "create" {
  description = "Whether to create the self-signed certificate"
  type        = bool
  default     = false
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "domain" {
  description = "Domain name for the certificate"
  type        = string
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}
