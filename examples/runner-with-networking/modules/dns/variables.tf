variable "project_id" {
  type        = string
  description = "The ID of the project in which to create the resources."
}

variable "name_prefix" {
  type        = string
  description = "The prefix for the resources to be created."
}

variable "proxy_domain" {
  type        = string
  description = "The domain name for the proxy."
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}

variable "create_dns_auth" {
  type        = bool
  description = "Whether to create a DNS authorization for the proxy."
  default     = true
}

variable "loadbalancer_type" {
  type        = string
  description = "Load balancer type: external or internal. Certificate Manager cert is only created for external."
  default     = "external"
}
