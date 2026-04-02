# Pub/Sub module for event-driven reconciliation

# Pub/Sub topic for compute events
resource "google_pubsub_topic" "compute_events" {
  name         = "${var.runner_name}-compute-events"
  project      = var.project_id
  kms_key_name = local.kms_key_name

  labels = var.labels

  # Enable message ordering if needed
  message_retention_duration = "604800s" # 7 days
}

# Pub/Sub subscription for the runner
resource "google_pubsub_subscription" "compute_events" {
  name    = "${var.runner_name}-compute-events-${var.runner_id}"
  topic   = google_pubsub_topic.compute_events.name
  project = var.project_id

  labels = var.labels

  # Reduced ack deadline for faster event processing
  ack_deadline_seconds = 60

  # Retry policy for failed message processing
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s" # Reduced from 600s for faster recovery
  }

  # Dead letter policy for failed messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }

  # Never expire the subscription
  expiration_policy {
    ttl = ""
  }

  # Enable message ordering
  enable_message_ordering = true

  # Message retention
  message_retention_duration = "604800s" # 7 days
  retain_acked_messages      = false

  lifecycle {
    create_before_destroy = false
  }
}

# Dead letter topic for failed messages
resource "google_pubsub_topic" "dead_letter" {
  name         = "${var.runner_name}-compute-events-dead-letter"
  project      = var.project_id
  kms_key_name = local.kms_key_name

  labels = merge(var.labels, {
    purpose = "dead-letter"
  })

  # Longer retention for debugging failed messages
  message_retention_duration = "604800s" # 7 days
}

# Dead letter subscription for monitoring/debugging
resource "google_pubsub_subscription" "dead_letter" {
  name    = "${var.runner_name}-compute-events-dead-letter-${var.runner_id}"
  topic   = google_pubsub_topic.dead_letter.name
  project = var.project_id

  labels = merge(var.labels, {
    purpose = "dead-letter-monitoring"
  })

  # Long ack deadline for manual inspection
  ack_deadline_seconds = 600

  # Keep messages for debugging
  retain_acked_messages      = true
  message_retention_duration = "604800s" # 7 days

  lifecycle {
    create_before_destroy = false
  }
}

# Enhanced Cloud Logging sink with better filtering
resource "google_logging_project_sink" "compute_events" {
  name        = "gitpod-compute-events-sink-${var.runner_id}"
  project     = var.project_id
  destination = "pubsub.googleapis.com/projects/${var.project_id}/topics/${google_pubsub_topic.compute_events.name}"

  # Filter for compute instance events only
  filter = <<-EOT
    resource.type="gce_instance"
    AND (
      (
        protoPayload.methodName="v1.compute.instances.insert"
        OR protoPayload.methodName="v1.compute.instances.delete"
        OR protoPayload.methodName="v1.compute.instances.stop"
        OR protoPayload.methodName="v1.compute.instances.start"
        OR protoPayload.methodName="beta.compute.instances.insert"
        OR protoPayload.methodName="beta.compute.instances.delete"
        OR protoPayload.methodName="beta.compute.instances.stop"
        OR protoPayload.methodName="beta.compute.instances.start"
      )
      AND (
        operation.last=true
        OR NOT operation.first=true
        OR NOT protoPayload.request
      )
    )
    AND severity >= "INFO"
    AND resource.labels.project_id="${var.project_id}"
  EOT

  # Ensure unique writer identity
  unique_writer_identity = true
}

# Grant Pub/Sub Publisher role to Cloud Logging service account
resource "google_pubsub_topic_iam_member" "cloud_logging_publisher" {
  topic   = google_pubsub_topic.compute_events.name
  role    = "roles/pubsub.publisher"
  member  = google_logging_project_sink.compute_events.writer_identity
  project = var.project_id
}

# Consolidated IAM binding for runner service account
resource "google_pubsub_subscription_iam_member" "runner_subscriber" {
  subscription = google_pubsub_subscription.compute_events.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${local.runner_sa_email}"
  project      = var.project_id
}

# Add monitoring access for dead letter queue
resource "google_pubsub_subscription_iam_member" "runner_dead_letter_viewer" {
  subscription = google_pubsub_subscription.dead_letter.name
  role         = "roles/pubsub.viewer"
  member       = "serviceAccount:${local.runner_sa_email}"
  project      = var.project_id
}
