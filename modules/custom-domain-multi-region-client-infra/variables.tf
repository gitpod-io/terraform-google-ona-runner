variable "project_id" {
  description = "GCP project ID where the client infrastructure will be deployed"
  type        = string
}

variable "service_attachments" {
  description = "Ona relay PSC service attachments keyed by GCP region"
  type = map(object({
    service_attachment_uri = string
    subnet_name            = string
  }))

  validation {
    condition     = length(var.service_attachments) > 0
    error_message = "service_attachments must contain at least one regional service attachment."
  }

  validation {
    condition = alltrue([
      for region, attachment in var.service_attachments :
      can(regex("/regions/${region}/serviceAttachments/", attachment.service_attachment_uri))
    ])
    error_message = "Each service attachment URI must use the region specified by its map key."
  }

  validation {
    condition = length(distinct([
      for attachment in values(var.service_attachments) : attachment.service_attachment_uri
    ])) == length(var.service_attachments)
    error_message = "Each service attachment URI must be unique."
  }
}

variable "vpc_network" {
  description = "Name of the VPC network that contains the regional subnets"
  type        = string
  default     = "default"
}

variable "domain_name" {
  description = "Custom domain name for the Ona instance"
  type        = string
}

variable "certificate_manager_cert_id" {
  description = "Full resource ID of a global Certificate Manager certificate"
  type        = string

  validation {
    condition     = can(regex("/locations/global/certificates/", var.certificate_manager_cert_id))
    error_message = "certificate_manager_cert_id must identify a global Certificate Manager certificate."
  }
}

variable "service_name" {
  description = "Name prefix for the resources"
  type        = string
  default     = "gitpod-custom-domain"
}
