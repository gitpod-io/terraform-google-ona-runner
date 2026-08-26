terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
}

variable "runner_id" {
  type = string
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "docker_config_json" {
  type      = string
  sensitive = true
}

resource "google_storage_bucket" "runner_assets" {
  name     = "${var.runner_id}-runner-assets"
  project  = var.project_id
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  labels = {
    gitpod-component = "runner-assets"
    managed-by       = "terraform"
  }
}

resource "google_storage_bucket_object" "docker_config" {
  count = 1

  name    = "docker-config.json"
  bucket  = google_storage_bucket.runner_assets.name
  content = var.docker_config_json

  content_type = "application/json"

  metadata = {
    uploaded_by = "terraform"
    runner_id   = var.runner_id
  }
}
