# Restricted runner with networking

This example creates a dedicated VPC for a restricted Ona runner. The runner has no proxy or load balancer, and environments reach its two fixed instances through private DNS and TLS.

Outbound connectivity is default-deny:

- Cloud NGFW allows public HTTPS only to `app.gitpod.io` by default.
- Private Service Connect's `all-apis` bundle carries `*.googleapis.com`, `*.pkg.dev`, and `*.gcr.io` traffic without public internet egress.
- VPC-internal traffic continues through the root module's more specific firewall rules.
- Google Cloud always permits each VM to reach its local metadata server for DNS, DHCP, NTP, and identity tokens.

There is no public Ona Private Service Connect service attachment for the canonical management-plane hostname. `app.gitpod.io` therefore keeps its public DNS resolution and reaches the internet through Cloud NAT after Cloud NGFW approves the exact FQDN. The custom-domain PSC relay is not a drop-in endpoint for `app.gitpod.io`: it requires a custom domain, a consumer HTTPS load balancer, and relay identity headers.

The example sets the VPC firewall-policy enforcement order to `BEFORE_CLASSIC_FIREWALL`. Approved traffic uses `goto_next`, preserving the root module's tag-based VPC firewall isolation; all remaining egress is denied before broad VPC egress rules can match.

## Usage

Copy `terraform.tfvars.example` to `terraform.tfvars`, fill in the runner values from Ona, and run:

```sh
terraform init
terraform plan
terraform apply
```

Development environments cannot reach SCMs, editor downloads, package registries, or arbitrary websites until their exact hostnames are added to `firewall_allowed_domains`. Cloud NGFW FQDN objects do not accept wildcard names. `firewall_allowed_ip_ranges` can add HTTPS CIDR exceptions when an endpoint does not have stable DNS.

Cloud NGFW resolves FQDN objects to destination IP addresses; it does not inspect TLS SNI or URLs. Use Cloud NGFW URL filtering and TLS inspection if workloads must distinguish an approved hostname from other services sharing the same destination IP.

The PSC endpoint IP must not overlap a VPC subnet, allocated range, or conflicting `/32` route. Change `psc_google_apis_ip` if `10.255.0.5` overlaps your network plan.

See the [Ona GCP access requirements](https://ona.com/docs/ona/runners/gcp/detailed-access-requirements), [Google APIs over PSC](https://cloud.google.com/vpc/docs/configure-private-service-connect-apis), and [Cloud NGFW FQDN egress quickstart](https://cloud.google.com/firewall/docs/quickstarts/configure-nwfwpolicy-fqdn-egress).
