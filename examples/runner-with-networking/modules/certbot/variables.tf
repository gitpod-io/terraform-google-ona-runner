variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "runner_name" {
  description = "Runner name prefix for resource naming"
  type        = string
}

variable "runner_id" {
  description = "Runner ID for labeling"
  type        = string
}

variable "runner_domain" {
  description = "Domain to obtain certificate for (e.g., runner.example.com)"
  type        = string
}

variable "acme_email" {
  description = "Email for Let's Encrypt registration"
  type        = string
}

variable "dns_zone_name" {
  description = "Cloud DNS managed zone name for DNS-01 challenges"
  type        = string
}

variable "dns_project_id" {
  description = "GCP project containing the Cloud DNS zone. Defaults to project_id."
  type        = string
  default     = ""
}

variable "schedule" {
  description = "Cron schedule for certificate renewal"
  type        = string
  default     = "0 3 * * *"
}

variable "run_initial_certbot" {
  description = "Trigger an initial certbot run during apply. Set to true only after NS delegation is in place, otherwise the DNS-01 challenge will fail."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}
