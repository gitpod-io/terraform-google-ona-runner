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
