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

Subsequent Terraform applies leave runner-created versions unchanged. A
`terraform destroy` removes the secret and its versions with the rest of the
runner infrastructure.

## Runner token storage modes

`runner_token_write_mode` defaults to `"legacy"`. This preserves the existing
runner-token resource and its `secret_data` with `ignore_changes`, so repeated
applies do not rewrite the initial token version.

New deployments can opt in to write-only storage, which prevents the runner
token from being persisted in Terraform state:

```hcl
runner_token                 = "" # Required compatibility input; unused in write_only mode.
runner_token_write_mode      = "write_only"
runner_token_secret_version  = 1
```

Supply the actual token only through the ephemeral input, for example:

```bash
export TF_VAR_runner_token_ephemeral='your-runner-token'
```

`runner_token` remains a required compatibility input; in write-only mode it
is not used to write the Secret Manager version. Increment
`runner_token_secret_version` only when intentionally writing a new token
version. **Do not switch an existing deployment from `legacy` to `write_only`.**
The two modes manage different Secret Manager version resources, so switching
might delete the legacy version before writing the replacement and interrupt
runner authentication. Write-only mode is for new deployments only.

## Releases

New stable releases are published roughly once a week. To get notified when a
release is available, subscribe to the Pub/Sub release notifications topic from
your own GCP project. See the
[Release Notifications](https://ona.com/docs/ona/runners/gcp/update-runner#release-notifications)
documentation for topic details, message format, and subscription examples.
