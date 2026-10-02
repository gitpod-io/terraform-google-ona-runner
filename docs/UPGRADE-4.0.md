# Upgrade from 3.x to 4.0

This guide covers upgrading an existing runner deployment from module version
3.2.2 to 4.0.0. If you use an earlier 3.x release, also review the intervening
[module release notes](https://github.com/gitpod-io/terraform-google-ona-runner/releases).

## Breaking requirements

| Dependency | Module 3.2.2 | Module 4.0.0 |
| --- | --- | --- |
| Terraform | `>= 1.3` | `>= 1.11` |
| `hashicorp/google` | `~> 6.0` | `>= 7.6, < 8.0` |
| `hashicorp/google-beta` | `~> 6.0` | `>= 7.6, < 8.0` |
| `hashicorp/tls` | `~> 4.2` | `>= 4.4, < 5.0` |

These requirements apply to the root runner module, including deployments with
`restrict_ingress = false`. They support ephemeral Secret Manager reads and
write-only TLS key inputs. Google and Google Beta require a major provider
upgrade; TLS remains on major version 4 with a higher minimum version.

The standalone `modules/custom-domain-client-infra` helper still permits Google
provider 6.x. This does not allow the root runner module to use provider 6.x.

## Prepare the upgrade

1. Upgrade Terraform to 1.11 or later on local machines, CI runners, and any
   HCP Terraform or Terraform Enterprise workspaces that apply this deployment.
2. Review the [Google provider 7 upgrade guide](https://registry.terraform.io/providers/hashicorp/google/latest/docs/guides/version_7_upgrade)
   for both Google providers. Follow its preparation guidance for existing 6.x
   configurations and resolve relevant deprecation warnings before upgrading.
3. Check provider constraints in your root configuration and other modules in
   the same deployment. A module requiring Google 6.x cannot share that provider
   with this module's 7.x requirement; upgrade or adjust that module first.
4. Retain the pre-upgrade configuration and provider lockfile, and ensure that
   your state backend has a recoverable pre-upgrade state version or backup.

## Update the configuration

In the existing runner module block, set `version = "4.0.0"` when using the
Terraform Registry. For a Git source, select `ref=4.0.0` instead. Keep the
existing module name, inputs, and deployment topology during this upgrade.
For a local or vendored module source, update the source checkout to the 4.0.0
release; the Registry `version` argument does not apply to local paths.

Merge these constraints into your existing root `terraform` block, preserving
other required providers and backend settings:

```hcl
terraform {
  required_version = ">= 1.11"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.6, < 8.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 7.6, < 8.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.4, < 5.0"
    }
  }
}
```

From the deployment's root directory, run:

```sh
terraform init -upgrade
terraform validate
terraform plan -out=upgrade-4.0.tfplan
```

`init -upgrade` can update other dependencies within their configured
constraints. Review the changes to `.terraform.lock.hcl` and retain the reviewed
file in version control. Do not delete it to bypass a version conflict.
The lockfile tracks providers, not remote module versions; the explicit module
version controls which release is selected.

## Review the plan and state moves

The module includes `moved` blocks for internal resource-address changes.
For an existing deployment keeping restricted ingress disabled, examples are:

| Old address within the module | New address within the module |
| --- | --- |
| `google_compute_region_instance_group_manager.runner` | `google_compute_region_instance_group_manager.runner["default"]` |
| `google_compute_region_instance_group_manager.proxy` | `google_compute_region_instance_group_manager.proxy[0]` |
| `google_compute_region_autoscaler.runner` | `google_compute_region_autoscaler.runner[0]` |

Terraform should show these as address moves rather than destroy/create actions
caused solely by the address change. Related proxy, firewall, and IAM resources
also have moves. Manual `terraform state mv` commands are not required for these
declared moves. Update custom import, targeting, or state-management scripts
that reference the old addresses, preserving the deployment's module prefix.

Do not expect a completely empty plan: the default runner and proxy images
advance from `20260814.483` in 3.2.2 to `20260928.1073` in this release. Unless
overridden, those defaults and the reported module version can update instance
templates and roll the managed instance groups. Provider 7 can also introduce
plan differences described in its upgrade guide. Review replacements and
deletions against your configuration before applying.

Restricted ingress remains disabled by default. Enabling it removes proxy and
load-balancer resources and changes the runner topology. Treat that as a
separate migration using the [restricted-runner documentation](../modules/restricted-runner/README.md)
and [deployer permissions](terraform_service_account_permissions.md), rather
than a step required to upgrade to 4.0.0.

## Apply and verify

After reviewing the saved plan, apply it through your normal approval workflow:

```sh
terraform apply upgrade-4.0.tfplan
```

Confirm that the configured runner and proxy MIGs settle, Terraform's health
validation succeeds when it runs, and an environment can start and connect.
Run another `terraform plan` and investigate unexpected remaining changes.

This guide describes the intended upgrade path; it does not establish that a
live 3.2.2-to-4.0.0 migration has been tested for your deployment. Test the upgrade
in a non-production deployment first. After applying, downgrading a version
constraint alone is not a guaranteed rollback of provider state changes;
review the upstream provider's downgrade guidance before attempting rollback.
