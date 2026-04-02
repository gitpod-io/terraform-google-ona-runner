terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# Enable required Google Cloud APIs for Ona Runner

# List of required services for Ona Runner
locals {
  required_services = [
    "compute.googleapis.com",              # Compute Engine API
    "redis.googleapis.com",                # Memorystore for Redis API
    "run.googleapis.com",                  # Cloud Run API (used for managed services)
    "vpcaccess.googleapis.com",            # VPC Access API
    "servicenetworking.googleapis.com",    # Service Networking API
    "artifactregistry.googleapis.com",     # Artifact Registry API
    "secretmanager.googleapis.com",        # Secret Manager API
    "logging.googleapis.com",              # Cloud Logging API
    "monitoring.googleapis.com",           # Cloud Monitoring API
    "iam.googleapis.com",                  # Identity and Access Management API
    "cloudresourcemanager.googleapis.com", # Cloud Resource Manager API (for IAM)
    "pubsub.googleapis.com",               # Cloud Pub/Sub API (for event-driven reconciliation)
    "certificatemanager.googleapis.com",   # Certificate Manager API (for wildcard SSL certificates)
    "dns.googleapis.com",                  # Cloud DNS API (for certificate validation)
    "iamcredentials.googleapis.com",       # IAM Credentials API (for access token generation)
    "storage.googleapis.com",              # Cloud Storage API (for build cache)
    "cloudfunctions.googleapis.com",       # Cloud Functions API (for auth proxy)
    "cloudscheduler.googleapis.com",       # Cloud Scheduler API (for certbot renewal)
  ]
}

# Enable all required services
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_services)

  project = var.project_id
  service = each.value

  # Don't disable on destroy to avoid breaking other resources
  disable_on_destroy = false

  # Allow dependent services to be destroyed
  disable_dependent_services = false

  timeouts {
    create = "10m"
    read   = "5m"
  }
}

# Data source to get project information
data "google_project" "current" {
  project_id = var.project_id
}

# Output the enabled services for verification
output "enabled_services" {
  description = "List of enabled Google Cloud services"
  value       = local.required_services
}

# Output project information
output "project_info" {
  description = "Information about the GCP project"
  value = {
    project_id     = data.google_project.current.project_id
    project_number = data.google_project.current.number
    name           = data.google_project.current.name
  }
}
