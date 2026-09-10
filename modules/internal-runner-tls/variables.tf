variable "project_id" {
  type        = string
  description = "Project containing the TLS secrets."
}

variable "region" {
  type        = string
  description = "Secret replica location when using CMEK."
}

variable "secret_prefix" {
  type        = string
  description = "Prefix for the bootstrap key and runner identity secrets."
}

variable "hostname" {
  type        = string
  description = "Private runner DNS name covered by the certificate."
}

variable "generation" {
  type        = number
  description = "Change to rotate the key and certificate after arranging overlapping public trust."
  default     = 1

  validation {
    condition     = var.generation >= 1 && floor(var.generation) == var.generation
    error_message = "generation must be a positive integer."
  }
}

variable "kms_key_name" {
  type        = string
  description = "Optional CMEK key; the caller grants Secret Manager access before creating secrets."
  default     = null
}

variable "labels" {
  type        = map(string)
  description = "Labels applied to both secrets."
  default     = {}
}
