variable "project_id" {
  description = "The GCP project ID where services will be enabled"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}
