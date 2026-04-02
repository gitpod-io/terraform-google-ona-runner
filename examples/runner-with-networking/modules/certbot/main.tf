# Certbot automation for automatic certificate management via Let's Encrypt.
# Creates a Cloud Run Job triggered by Cloud Scheduler that uses DNS-01 challenges
# against Cloud DNS to obtain and renew wildcard certificates, then writes them
# to Secret Manager for pickup by proxy VMs.
#
# Required GCP APIs (enabled by the services module):
#   - run.googleapis.com           (Cloud Run)
#   - cloudscheduler.googleapis.com (Cloud Scheduler)
#   - secretmanager.googleapis.com  (Secret Manager)
#   - dns.googleapis.com            (Cloud DNS)
#   - storage.googleapis.com        (GCS for certbot state)

locals {
  dns_project = var.dns_project_id != "" ? var.dns_project_id : var.project_id
  secret_name = "${var.runner_name}-certbot-cert"
}

# ================================
# SECRET MANAGER
# ================================

resource "google_secret_manager_secret" "cert" {
  secret_id = local.secret_name
  project   = var.project_id

  replication {
    auto {}
  }

  labels = merge(var.labels, {
    managed-by = "terraform"
    component  = "certbot"
    runner-id  = var.runner_id
  })
}

# ================================
# SERVICE ACCOUNT
# ================================

resource "google_service_account" "certbot" {
  account_id   = "${var.runner_name}-certbot"
  display_name = "Certbot certificate manager for ${var.runner_name}"
  project      = var.project_id
}

# ================================
# IAM - DNS PERMISSIONS
# ================================

data "google_dns_managed_zone" "zone" {
  name    = var.dns_zone_name
  project = local.dns_project
}

# Zone-scoped dns.admin for DNS-01 challenge record management
resource "google_dns_managed_zone_iam_member" "dns_admin" {
  project      = local.dns_project
  managed_zone = data.google_dns_managed_zone.zone.name
  role         = "roles/dns.admin"
  member       = "serviceAccount:${google_service_account.certbot.email}"
}

# Project-level dns.reader so certbot can discover zones
resource "google_project_iam_member" "dns_reader" {
  project = local.dns_project
  role    = "roles/dns.reader"
  member  = "serviceAccount:${google_service_account.certbot.email}"
}

# ================================
# IAM - SECRET MANAGER PERMISSIONS
# ================================

resource "google_secret_manager_secret_iam_member" "cert_writer" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.cert.secret_id
  role      = "roles/secretmanager.secretVersionAdder"
  member    = "serviceAccount:${google_service_account.certbot.email}"
}

resource "google_secret_manager_secret_iam_member" "cert_reader" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.cert.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.certbot.email}"
}

# ================================
# GCS BUCKET FOR CERTBOT STATE
# ================================

resource "google_storage_bucket" "state" {
  name          = "${var.runner_name}-certbot-state"
  project       = var.project_id
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }

  versioning {
    enabled = true
  }

  labels = merge(var.labels, {
    managed-by = "terraform"
    component  = "certbot"
    runner-id  = var.runner_id
  })
}

resource "google_storage_bucket_iam_member" "state" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.certbot.email}"
}

# Upload the entrypoint script to the state bucket
resource "google_storage_bucket_object" "entrypoint" {
  name         = "certbot-entrypoint.sh"
  bucket       = google_storage_bucket.state.name
  source       = "${path.module}/files/certbot-entrypoint.sh"
  content_type = "application/x-shellscript"
}

# ================================
# CLOUD RUN JOB
# ================================

resource "google_cloud_run_v2_job" "certbot" {
  name                = "${var.runner_name}-certbot"
  location            = var.region
  project             = var.project_id
  deletion_protection = false

  labels = merge(var.labels, {
    managed-by = "terraform"
    component  = "certbot"
    runner-id  = var.runner_id
  })

  template {
    task_count = 1

    template {
      max_retries = 1
      timeout     = "600s"

      service_account = google_service_account.certbot.email

      containers {
        image   = "certbot/dns-google:latest"
        command = ["/bin/sh"]
        args    = ["/mnt/certbot-state/certbot-entrypoint.sh"]

        env {
          name  = "RUNNER_DOMAIN"
          value = var.runner_domain
        }
        env {
          name  = "DNS_PROJECT_ID"
          value = local.dns_project
        }
        env {
          name  = "ACME_EMAIL"
          value = var.acme_email
        }
        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }
        env {
          name  = "CERT_SECRET_NAME"
          value = google_secret_manager_secret.cert.secret_id
        }

        volume_mounts {
          name       = "certbot-state"
          mount_path = "/mnt/certbot-state"
        }

        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }
      }

      volumes {
        name = "certbot-state"
        gcs {
          bucket    = google_storage_bucket.state.name
          read_only = false
        }
      }
    }
  }

  depends_on = [
    google_storage_bucket_object.entrypoint,
  ]
}

# ================================
# CLOUD SCHEDULER
# ================================

resource "google_cloud_scheduler_job" "certbot" {
  name     = "${var.runner_name}-certbot-renew"
  project  = var.project_id
  region   = var.region
  schedule = var.schedule

  description = "Triggers certbot certificate renewal for ${var.runner_domain}"

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/${google_cloud_run_v2_job.certbot.name}:run"

    oauth_token {
      service_account_email = google_service_account.certbot.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  retry_config {
    retry_count = 1
  }
}

resource "google_cloud_run_v2_job_iam_member" "invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.certbot.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.certbot.email}"
}

# ================================
# INITIAL CERTIFICATE ISSUANCE
# ================================

# Use the Terraform provider's credentials to trigger the initial run,
# avoiding any dependency on local gcloud CLI authentication.
data "google_client_config" "current" {}

# Trigger the first certbot run during apply. Gated by var.run_initial_certbot
# because NS delegation must be in place before the DNS-01 challenge can succeed.
#
# Recommended workflow:
#   1. terraform apply                          (creates infra, skips certbot run)
#   2. Set up NS delegation using output NS records
#   3. terraform apply -var run_initial_certbot=true  (issues the certificate)
#
# To re-trigger later: terraform apply -replace='module.certbot[0].null_resource.initial_run[0]'
resource "null_resource" "initial_run" {
  count = var.run_initial_certbot ? 1 : 0

  triggers = {
    entrypoint = google_storage_bucket_object.entrypoint.md5hash
    domain     = var.runner_domain
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Triggering initial certbot certificate issuance..."

      # Trigger the Cloud Run Job via REST API
      RESPONSE=$(curl -s -w "\n%%{http_code}" -X POST \
        -H "Authorization: Bearer ${data.google_client_config.current.access_token}" \
        -H "Content-Type: application/json" \
        "https://${var.region}-run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/${google_cloud_run_v2_job.certbot.name}:run")
      HTTP_CODE=$(echo "$RESPONSE" | tail -1)
      BODY=$(echo "$RESPONSE" | sed '$d')

      if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
        echo "ERROR: Failed to trigger certbot job (HTTP $HTTP_CODE): $BODY"
        exit 1
      fi

      echo "Certbot job triggered successfully (HTTP $HTTP_CODE)"

      # Extract the execution name from the response to poll for completion
      EXECUTION=$(echo "$BODY" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
      if [ -z "$EXECUTION" ]; then
        echo "WARNING: Could not extract execution name, skipping wait"
        exit 0
      fi

      echo "Waiting for execution to complete: $EXECUTION"

      # Poll until the execution completes (timeout after 10 minutes)
      TIMEOUT=600
      ELAPSED=0
      INTERVAL=15
      while [ $ELAPSED -lt $TIMEOUT ]; do
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))

        STATUS_RESPONSE=$(curl -s \
          -H "Authorization: Bearer ${data.google_client_config.current.access_token}" \
          "https://${var.region}-run.googleapis.com/v2/$EXECUTION")

        # Check if the execution has completed
        COMPLETED=$(echo "$STATUS_RESPONSE" | grep -o '"completionTime":"[^"]*"' || true)
        if [ -n "$COMPLETED" ]; then
          # Check if it succeeded
          SUCCEEDED=$(echo "$STATUS_RESPONSE" | grep -o '"succeededCount":[0-9]*' | cut -d: -f2)
          if [ "$SUCCEEDED" = "1" ]; then
            echo "Certbot execution completed successfully"
            exit 0
          else
            echo "ERROR: Certbot execution failed"
            echo "$STATUS_RESPONSE" | grep -o '"message":"[^"]*"' || true
            exit 1
          fi
        fi

        echo "  Still running... ($ELAPSED/$TIMEOUT seconds)"
      done

      echo "ERROR: Timed out waiting for certbot execution after $TIMEOUT seconds"
      exit 1
    EOT
  }

  depends_on = [
    google_cloud_run_v2_job.certbot,
    google_cloud_run_v2_job_iam_member.invoker,
    google_storage_bucket_object.entrypoint,
    google_secret_manager_secret_iam_member.cert_writer,
    google_secret_manager_secret_iam_member.cert_reader,
    google_dns_managed_zone_iam_member.dns_admin,
    google_project_iam_member.dns_reader,
    google_storage_bucket_iam_member.state,
  ]
}
