terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
    google-beta = {
      source = "hashicorp/google-beta"
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

resource "google_compute_instance_template" "runner" {
  name_prefix  = "test-runner-runner-"
  project      = var.project_id
  machine_type = "c4-standard-4"
  region       = var.region

  disk {
    source_image = "cos-cloud/cos-stable"
    boot         = true
  }

  network_interface {
    network = "default"
  }

  metadata = {
    user-data = "DOCKER_CONFIG_BUCKET_NAME=${google_storage_bucket.runner_assets.name}"
  }
}

resource "google_compute_instance_template" "proxy" {
  name_prefix  = "test-runner-proxy-"
  project      = var.project_id
  machine_type = "c4-standard-2"
  region       = var.region

  disk {
    source_image = "cos-cloud/cos-stable"
    boot         = true
  }

  network_interface {
    network = "default"
  }

  metadata = {
    user-data = "DOCKER_CONFIG_BUCKET_NAME=${google_storage_bucket.runner_assets.name}"
  }
}

resource "google_compute_region_instance_group_manager" "runner" {
  provider = google-beta

  name               = "test-runner-group"
  base_instance_name = "test-runner"
  project            = var.project_id
  region             = var.region

  version {
    instance_template = google_compute_instance_template.runner.id
  }
}

resource "google_compute_region_instance_group_manager" "proxy" {
  name               = "test-runner-proxy-group"
  base_instance_name = "test-runner-proxy"
  project            = var.project_id
  region             = var.region

  version {
    instance_template = google_compute_instance_template.proxy.id
  }
}
