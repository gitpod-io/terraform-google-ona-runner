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

## Restricted ingress preparation

`restrict_ingress = true` reserves two static internal IPv4 addresses in the
runner subnet and creates a private Cloud DNS A record containing both addresses.
The option defaults to `false` and is also available in the
`runner-with-networking` example.

This is the first stage of restricted ingress support. The addresses are not yet
attached to runner VMs, and enabling this option does not yet restrict ingress,
remove the proxy or load balancer, or enable internal LLM traffic. IP attachment
and replacement, HTTPS, and environment trust require follow-up support.

The hostname is `runner.ona-<runner_id>.internal`, scoped to the configured VPC.
It uses a separate private zone so it does not shadow the existing runner domain.
Read it from the `internal_runner_hostname` output and the addresses from
`internal_runner_ips`. With the option disabled, these outputs are `null` and
an empty list, respectively. Disabling the option removes the DNS zone, record,
and reservations.

Cloud DNS returns both addresses without checking whether a runner is listening.
Before using this name for LLM traffic, IP ownership and client connection
fallback must be implemented and verified.

The Cloud DNS API must be enabled in the runner project. For Shared VPC, the
reservations use the host project's runner subnet and the private zone is bound
to the host network. See the
[Terraform deployer permissions](docs/terraform_service_account_permissions.md#restricted-ingress-preparation)
for the additional DNS permissions; the runner service account needs no DNS
permissions for these Terraform-managed records.

## Runner secrets key lifecycle

Terraform creates the Secret Manager secret and its IAM policy, but it does not
manage a secret version for the runner secrets key. The runner writes the first
version, verifies that Secret Manager returns the same key, and then removes the
legacy copy from Redis. This keeps the key material out of Terraform state.

Subsequent Terraform applies leave runner-created versions unchanged. A
`terraform destroy` removes the secret and its versions with the rest of the
runner infrastructure.

## Releases

New stable releases are published roughly once a week. To get notified when a
release is available, subscribe to the Pub/Sub release notifications topic from
your own GCP project. See the
[Release Notifications](https://ona.com/docs/ona/runners/gcp/update-runner#release-notifications)
documentation for topic details, message format, and subscription examples.
