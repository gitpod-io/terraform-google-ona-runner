terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

variable "project_id" {
  type = string
}

variable "environment_vm_sa_email" {
  type = string
}

resource "google_project_iam_member" "env_vm_artifact_registry" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${var.environment_vm_sa_email}"
}
