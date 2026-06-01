variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "vpc_name" {
  description = "Name of the VPC to use"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet"
  type        = string
}

variable "additional_regions" {
  description = "Additional regions where environment VM subnets and NAT should be created"
  type = list(object({
    region      = string
    subnet_cidr = string
  }))
  default = []

  validation {
    condition = alltrue([
      for r in var.additional_regions :
      r.region != "" && r.subnet_cidr != ""
    ])
    error_message = "Each additional region must set region and subnet_cidr."
  }
}

variable "create_private_network" {
  description = "Create a private network"
  type        = bool
  default     = false
}
