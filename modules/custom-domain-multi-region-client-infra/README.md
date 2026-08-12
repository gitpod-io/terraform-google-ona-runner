# Multi-region custom domain client infrastructure

This Terraform module connects a custom domain to one or more regional Ona relay Private Service Connect (PSC) service attachments. It creates a region-matched PSC network endpoint group (NEG) for each attachment and uses the NEGs as backends of a global external HTTPS load balancer.

Use this module when clients in more than one region need one public custom-domain address. Continue to use [`../custom-domain-client-infra`](../custom-domain-client-infra) for a regional or internal load balancer.

## Understand the request path

```text
Client
  -> global external HTTPS load balancer
  -> PSC NEG in a service attachment's region
  -> Ona relay PSC service attachment
  -> Ona relay
```

The load balancer adds `X-Gitpod-GCP-ID` with the customer project ID. The relay checks that the project has an accepted connection to one of its configured service attachments before it forwards the request.

The module does not create a separate PSC forwarding-rule endpoint. A PSC NEG is the endpoint used by the load balancer backend.

## Meet the prerequisites

Provide the following resources before applying the module:

- A VPC network in the customer project.
- One subnet in each service attachment region. The subnets must belong to the same VPC network.
- One Ona relay service attachment URI per region. Each URI must match its map key.
- Producer load balancers with global access enabled before their service attachments are created.
- A global Certificate Manager certificate for the custom domain.

The module does not require a VPN or a proxy-only subnet.

## Configure the module

```hcl
module "custom_domain_client_infra" {
  source = "./modules/custom-domain-multi-region-client-infra"

  project_id  = "your-gcp-project-id"
  vpc_network = "default"

  service_attachments = {
    us-central1 = {
      service_attachment_uri = "https://www.googleapis.com/compute/v1/projects/relay-project/regions/us-central1/serviceAttachments/relay-service-central"
      subnet_name            = "default-us-central1"
    }
    us-east4 = {
      service_attachment_uri = "https://www.googleapis.com/compute/v1/projects/relay-project/regions/us-east4/serviceAttachments/relay-service-east"
      subnet_name            = "default-us-east4"
    }
  }

  domain_name = "gitpod.example.com"
  certificate_manager_cert_id = "//certificatemanager.googleapis.com/projects/your-gcp-project-id/locations/global/certificates/your-cert-name"
}
```

Deploy one region first by supplying one map entry. Add another entry after the corresponding regional service attachment is available.

```bash
terraform init
terraform plan
terraform apply
```

Point the custom domain's public DNS record at `module.custom_domain_client_infra.load_balancer_ip`.

## Account for regional availability

Every PSC NEG must be in the same region as its target service attachment. PSC global access does not remove that requirement.

Multiple regional PSC NEGs let the global load balancer use regional connections. They provide full regional availability only when the producer also runs an independent relay backend in each region. If all service attachments route to one regional relay backend, that backend remains a single regional dependency.

## Inputs

| Name | Description | Type | Default |
| --- | --- | --- | --- |
| `project_id` | Customer GCP project ID | `string` | Required |
| `service_attachments` | PSC attachment URI and subnet name keyed by region | `map(object)` | Required |
| `vpc_network` | VPC network name | `string` | `"default"` |
| `domain_name` | Custom domain name | `string` | Required |
| `certificate_manager_cert_id` | Global Certificate Manager certificate resource ID | `string` | Required |
| `service_name` | Resource name prefix | `string` | `"gitpod-custom-domain"` |

## Outputs

| Name | Description |
| --- | --- |
| `load_balancer_ip` | Global external load balancer IP address |
| `domain_name` | Configured custom domain name |
| `ssl_certificate_used` | Certificate Manager certificate resource ID |
| `psc_network_endpoint_groups` | PSC NEG resource IDs keyed by region |
