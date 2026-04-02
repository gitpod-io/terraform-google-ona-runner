# GCP Runner Release Notifications

Ona publishes Pub/Sub messages when new GCP runner releases are available. Subscribe to receive push notifications instead of polling for updates.

## Topic

| Property | Value |
|---|---|
| Project | `gitpod-next-production` |
| Topic | `gcp-runner-releases` |
| Full name | `projects/gitpod-next-production/topics/gcp-runner-releases` |
| Message retention | 7 days |
| Access | Any authenticated GCP user can subscribe |

## Events

Notifications are published only for **stable** releases.

| Event Type | Description |
|---|---|
| `release.stable` | Release promoted to stable |

## Message Format

### Attributes

Every message includes these attributes for filtering:

- `event_type` — `release.stable`
- `version` — Release version string (e.g., `20250115.0`)
- `source` — What triggered the notification:
  - `ci_stable_promotion` — Release promoted to stable
  - `gcs_notification` — Stable manifest updated in GCS (automatic)

### Payload

CI-published messages contain the release manifest plus Terraform module change context:

```json
{
  "version": "20250115.0",
  "commit": "abc123def",
  "release_date": "2025-01-15T00:30:00Z",
  "infrastructure_version": "latest",
  "proxy_image": "us-docker.pkg.dev/gitpod-next-production/gitpod-next/gitpod-proxy:20250115.0",
  "runner_image": "us-docker.pkg.dev/gitpod-next-production/gitpod-next/gitpod-gcp-runner:20250115.0",
  "prometheus_image": "us-docker.pkg.dev/gitpod-next-production/gitpod-next/prometheus:v3.5.0",
  "supervisor_url": "https://storage.googleapis.com/gitpod-runner-releases/gcp/releases/20250115.0/supervisor-amd64.xz",
  "supervisor_version": "20250115.0",
  "cli_url": "https://storage.googleapis.com/gitpod-runner-releases/gcp/releases/20250115.0/gitpod-linux-amd64",
  "download_url": "https://storage.googleapis.com/gitpod-runner-releases/gcp/releases/20250115.0/gitpod-gcp-manifest.json",
  "vm_image": "projects/gitpod-next-production/global/images/ona-environment-20250115-1041",
  "terraform_changes": [
    "- Add network firewall rule for proxy health checks (a1b2c3d)",
    "- Update default machine type to n2d-standard-16 (e4f5g6h)"
  ],
  "iam_changes_detected": false
}
```

| Field | Type | Description |
|---|---|---|
| `terraform_changes` | `string[]` | Terraform module commits since the previous release, excluding automated image updates. Empty array if no changes. |
| `iam_changes_detected` | `boolean` | `true` if IAM-related files (`iam.tf`, `docs/iam.md`, etc.) changed in this release. Signals that IAM configuration may need updating. |

GCS notifications use the standard [Cloud Storage notification format](https://cloud.google.com/storage/docs/pubsub-notifications#payload).

## Subscribing

### Using gcloud

Create a pull subscription in your project:

```bash
gcloud pubsub subscriptions create ona-runner-releases \
  --project=YOUR_PROJECT_ID \
  --topic=projects/gitpod-next-production/topics/gcp-runner-releases \
  --ack-deadline=60
```

Pull messages:

```bash
gcloud pubsub subscriptions pull ona-runner-releases \
  --project=YOUR_PROJECT_ID \
  --auto-ack \
  --limit=10
```

### Using Terraform

```hcl
resource "google_pubsub_subscription" "ona_runner_releases" {
  name    = "ona-runner-releases"
  project = var.project_id

  topic = "projects/gitpod-next-production/topics/gcp-runner-releases"

  ack_deadline_seconds = 60

  # Optional: receive only CI-published messages (skip GCS notification duplicates)
  # filter = "attributes.source = \"ci_stable_promotion\""

  # Optional: dead-letter policy
  # dead_letter_policy {
  #   dead_letter_topic     = google_pubsub_topic.dead_letter.id
  #   max_delivery_attempts = 5
  # }

  # Optional: retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}
```

### Filtering

Use [Pub/Sub subscription filters](https://cloud.google.com/pubsub/docs/subscription-message-filter) to receive only the events you care about:

| Filter | Effect |
|---|---|
| `attributes.source = "ci_stable_promotion"` | CI-published stable promotions only (full manifest payload, no GCS duplicate) |
| `attributes.source = "gcs_notification"` | GCS-triggered notifications only |

### Push Subscription

To receive notifications via HTTP webhook:

```hcl
resource "google_pubsub_subscription" "ona_runner_releases_push" {
  name    = "ona-runner-releases-push"
  project = var.project_id

  topic = "projects/gitpod-next-production/topics/gcp-runner-releases"

  push_config {
    push_endpoint = "https://your-endpoint.example.com/ona-releases"
  }

  filter = "attributes.source = \"ci_stable_promotion\""
}
```
