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

## Project Metadata Mode

By default this module uses `google_compute_project_metadata` (authoritative),
which manages **all** project-level metadata. Any metadata keys not declared in
this module will be removed on `terraform apply`.

If other systems or Terraform modules manage project metadata in the same GCP
project, set `use_authoritative_project_metadata = false` to switch to per-key
`google_compute_project_metadata_item` resources. This only manages the keys
the module needs (`enable-oslogin`, `gitpod-runner-id`) and leaves everything
else untouched.

```hcl
module "runner" {
  source = "gitpod-io/ona-runner/google"
  # ...
  use_authoritative_project_metadata = false
}
```

### Migrating an existing deployment to per-key metadata

Switching an existing deployment from authoritative to per-key requires a state
migration. Without it, Terraform will try to destroy the old resource and create
the new ones, which can fail or cause a brief metadata gap.

```bash
# 1. Remove the old authoritative resource from state
terraform state rm 'module.runner.google_compute_project_metadata.runner_metadata'

# 2. Import the individual keys into the new resources
terraform import 'module.runner.google_compute_project_metadata_item.enable_oslogin[0]' 'projects/<PROJECT_ID>/enable-oslogin'
terraform import 'module.runner.google_compute_project_metadata_item.runner_id[0]' 'projects/<PROJECT_ID>/gitpod-runner-id'

# 3. Apply — should show no changes
terraform apply
```

Replace `<PROJECT_ID>` with your GCP project ID and adjust the module path if
your module block uses a different name.

## Releases

New stable releases are published roughly once a week. To get notified when a
release is available, subscribe to the Pub/Sub release notifications topic from
your own GCP project. See the
[Release Notifications](https://ona.com/docs/ona/runners/gcp/update-runner#release-notifications)
documentation for topic details, message format, and subscription examples.
