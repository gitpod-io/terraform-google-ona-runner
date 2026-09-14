# Restricted Ona runner

This module is a thin policy wrapper around the root module. It enables restricted ingress, removes the proxy and load balancer, and gives the two runner instances stable internal IP addresses behind private DNS and TLS.

The VPC must provide the outbound connectivity needed by the runner. Use the [`restricted-runner-with-networking`](../../examples/restricted-runner-with-networking) example for a default-deny Cloud NGFW policy and Private Service Connect access to Google APIs.

```hcl
module "runner" {
  source = "gitpod-io/ona-runner/google//modules/restricted-runner"

  project_id         = "my-project"
  runner_id          = "00000000-0000-4000-8000-000000000000"
  runner_token       = var.runner_token
  runner_name        = "ona-runner"
  region             = "us-central1"
  zones              = ["us-central1-a", "us-central1-b"]
  vpc_name           = "ona-runner-vpc"
  runner_subnet_name = "ona-runner-subnet"
}
```

## Runner configuration

The wrapper forwards operational and security configuration to the root module
while keeping restricted ingress and its fixed two-instance topology
authoritative. Supported optional inputs include:

- `development_version`, `ssh_port`, and `service_ports`
- `proxy_config` and `ca_certificate`
- `auth_proxy_cert_rotation_triggers` and
  `internal_runner_endpoint_version`
- `create_cmek` and `kms_key_name`
- `pre_created_service_accounts` for the runner and environment VMs
- `custom_images`
- `enable_agents` and `enable_cross_zone_restart`
- `use_authoritative_project_metadata`

Load-balancer, proxy VM, public certificate, runner VM sizing, and Redis sizing
inputs are intentionally not exposed. The wrapper does not create those edge
resources and owns the runner topology required for stable internal addresses.

When `pre_created_service_accounts.attach_iam_policies` is `false`, provision
the required IAM before applying. The restricted module does not expose proxy
VM service-account or image settings because restricted mode creates no proxy
VMs.
