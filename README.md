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

## Requirements

The root module requires Terraform 1.11+, Google and Google Beta providers 7.6+
(below 8.0), and TLS provider 4.4+ (below 5.0). These versions support write-only
certificate keys and ephemeral Secret Manager reads for internal runner TLS.

When upgrading an existing deployment, review the
[Google provider 7 upgrade guide](https://registry.terraform.io/providers/hashicorp/google/latest/docs/guides/version_7_upgrade)
and inspect a plan before applying. Keep the deployment's provider lockfile
and update it intentionally with `terraform init -upgrade`.

## Example

The [`runner-with-networking`](./examples/runner-with-networking/) example
provides a full infrastructure setup including VPC, DNS, and certificates.

## Restricted ingress

`restrict_ingress = true` reserves two static internal IPv4 addresses in the
runner subnet, assigns them to two fixed instances in the runner MIG, and creates
a private Cloud DNS A record containing both addresses. The option defaults to
`false` and is also available in the `runner-with-networking` example.

GCP does not support autoscaling a MIG with stateful IP configuration, so this
mode uses exactly two runner instances. Updates recreate one instance at a time
without surge or cross-zone redistribution, preserving each instance's address.
The firewall permits TCP port 8089 only from environment-tagged VMs to the runner
instances. This option does not remove the existing proxy or load balancer.

The hostname is `runner.ona-<runner_id>.internal`, scoped to the configured VPC.
It uses a separate private zone so it does not shadow the existing runner domain.
Read it from the `internal_runner_hostname` output and the addresses from
`internal_runner_ips`. With the option disabled, these outputs are `null` and
an empty list, respectively. Disabling the option removes the DNS zone, record,
and reservations, removes the internal TLS secrets, and removes their public
certificate from the trust bundle.

Cloud DNS returns both addresses without checking whether a runner is listening.
During replacement or failure, clients must be able to connect to the other
address.

The Cloud DNS API must be enabled in the runner project. For Shared VPC, the
reservations use the host project's runner subnet and the private zone is bound
to the host network. See the
[Terraform deployer permissions](docs/terraform_service_account_permissions.md#restricted-ingress-preparation)
for the additional DNS permissions; the runner service account needs no DNS
permissions for these Terraform-managed records.

## Internal runner endpoint

With `restrict_ingress = true`, Terraform creates a bootstrap key secret and a
runner certificate/key secret, and publishes the public certificate in the GCS
trust bundle. It injects the endpoint, port, secret name, and exact secret
version into the runner container. Enable restricted ingress only with a runner
release that supports the internal endpoint configuration.

The internal TLS private key travels only through ephemeral values and
write-only inputs. It is stored in Secret Manager, not Terraform state or saved
plans. Terraform rereads the persisted key ephemerally before issuing the
certificate so a failed apply can retry without changing the identity. This
applies to the new internal TLS identity; other existing certificate and secret
resources retain their current state behavior.

The runner receives a `roles/secretmanager.secretAccessor` grant on the pair
secret when this module manages IAM. Environments receive public trust through
GCS and need no TLS-secret access. This grant does not narrow the runner's
existing project-level permissions. For externally managed IAM, grant the runner
access to the pair secret before activation. The Terraform deployer needs access
to both secrets and their versions. See
[deployer permissions](docs/terraform_service_account_permissions.md#internal-runner-endpoint-preparation).

The certificate is self-signed, covers the internal DNS name, and is valid for
ten years. Ordinary runner replacement reuses the selected identity. This module
does not perform live certificate reload or distribute trust to already running
environments.

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
