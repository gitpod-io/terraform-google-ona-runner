# Ona GCP Runner

[![Build with Ona](https://gitpod.io/button/open-in-gitpod.svg)](https://gitpod.io/#https://github.com/gitpod-io/terraform-google-ona-runner)

This is the Terraform module for the Ona GCP Runner. It deploys an
[Ona](https://ona.com) runner in your Google Cloud VPC, where each development
environment runs as a Compute Engine instance inside your project — source code
and credentials never leave your infrastructure.

> GCP Runners require an [Enterprise plan](https://ona.com/pricing).
> To get access, [contact our sales](https://ona.com/contact/sales).

Refer to [the Ona documentation](https://ona.com/docs/ona/runners/gcp/overview)
for setup instructions, configuration options, and troubleshooting.

---

<p align="center">
  <img src="./docs/images/arch-diagram.png" alt="GCP Runner architecture" width="700" />
</p>

---

## Example

The [`runner-with-networking`](./examples/runner-with-networking/) example
provides a full infrastructure setup including VPC, DNS, and certificates.

## Runner secrets key lifecycle

Terraform creates the Secret Manager secret and its IAM policy, but it does not
manage a secret version for the runner secrets key. The runner writes the first
version, verifies that Secret Manager returns the same key, and then removes the
legacy copy from Redis. This keeps the key material out of Terraform state.

Deletion protection is enabled by default. To intentionally destroy the module,
set `runner_secrets_key_deletion_protection = false` and apply that change before
running `terraform destroy`. Secret-version destruction is delayed for 30 days.

## Releases

New stable releases are published roughly once a week. To get notified when a
release is available, subscribe to the Pub/Sub release notifications topic from
your own GCP project. See the
[Release Notifications](https://ona.com/docs/ona/runners/gcp/update-runner#release-notifications)
documentation for topic details, message format, and subscription examples.
