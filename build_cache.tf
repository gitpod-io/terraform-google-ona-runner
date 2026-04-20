# GCS Bucket for BuildKit build cache
resource "google_storage_bucket" "build_cache" {
  name     = "gitpod-runner-buildcache-${var.runner_id}"
  location = var.region
  project  = var.project_id

  # Storage configuration
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  default_event_based_hold    = false
  requester_pays              = false
  force_destroy               = true

  # Lifecycle management - automatic cleanup of old cache data (30 days for production)
  lifecycle_rule {
    condition {
      age                   = 30 # Hardcoded to 30 days for production
      matches_storage_class = ["STANDARD"]
    }
    action {
      type = "Delete"
    }
  }

  # Clean up incomplete multipart uploads
  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }

  # Versioning disabled for cache data (not needed)
  versioning {
    enabled = false
  }

  # CMEK encryption (optional)
  dynamic "encryption" {
    for_each = local.kms_key_name != null ? [1] : []
    content {
      default_kms_key_name = local.kms_key_name
    }
  }

  # Labels for resource management
  labels = merge(var.labels, {
    gitpod-component = "build-cache"
    managed-by       = "terraform"
    purpose          = "buildkit-cache"
  })
}
