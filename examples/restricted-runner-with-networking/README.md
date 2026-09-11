# Restricted runner with networking

This example creates a dedicated VPC for a restricted Ona runner. The runner has no proxy or load balancer, and environments reach its two fixed instances through private DNS and TLS.

Outbound connectivity is default-deny:

- Cloud NGFW allows public HTTPS only to `app.gitpod.io` by default.
- Private Service Connect's `all-apis` bundle carries `*.googleapis.com`, `*.pkg.dev`, and `*.gcr.io` traffic without public internet egress.
- VPC-internal traffic continues through the root module's more specific firewall rules.
- Google Cloud always permits each VM to reach its local metadata server for DNS, DHCP, NTP, and identity tokens.

There is no public Ona Private Service Connect service attachment for the canonical management-plane hostname. `app.gitpod.io` therefore keeps its public DNS resolution and reaches the internet through Cloud NAT after Cloud NGFW approves the exact FQDN. The custom-domain PSC relay is not a drop-in endpoint for `app.gitpod.io`: it requires a custom domain, a consumer HTTPS load balancer, and relay identity headers.

The example sets the VPC firewall-policy enforcement order to `BEFORE_CLASSIC_FIREWALL`. Approved traffic uses `goto_next`, preserving the root module's tag-based VPC firewall isolation; all remaining egress is denied before broad VPC egress rules can match.

## Security evidence

The example records cloud-generated evidence outside the environment VM:

- Cloud DNS query logs, including the source VM and resolved name. Cached responses are not repeated.
- VPC Flow Logs with five-second aggregation, full secondary sampling, and all available metadata.
- Cloud NAT connection and error logs.
- Cloud NGFW denial logs. Approved `goto_next` rules cannot emit firewall-policy logs, so the root module's final classic egress rule records allowed environment connections instead.
- Cloud Audit Logs for the runner's control plane and every Google Cloud service available to the environment VM service account.

These records are routed to a dedicated Log Analytics bucket with 90-day retention. The retention policy is permanently locked, and Terraform abandons the bucket during destroy so retained evidence is not deleted. `security_log_bucket_location` is the only observability setting because data-residency requirements vary between deployments.

Environment VM names contain the Ona environment ID, which provides direct attribution in DNS, firewall, flow, and NAT records. Google API audit records identify the shared environment VM service account, not an individual environment. Correlate audit timestamps and caller IPs with the network records; concurrent activity can remain ambiguous.

High-volume VPC Flow Logs and Data Access audit logs incur Cloud Logging ingestion and retention costs. The locked bucket cannot be deleted until its retention constraints permit it, including after the rest of the runner is destroyed.

Cloud Monitoring policies create incidents for denied egress, denied environment API calls, restricted-runner security-control changes, more than 100 NXDOMAIN responses in five minutes, and Cloud NGFW inspection fail-open events. Security Command Center Event Threat Detection can additionally analyze the DNS, NAT, firewall, and flow logs when it is activated for the project or organization.

Cloud-generated records are the forensic source of truth. The environment VM service account can write application logs and metrics, so guest-authored telemetry must be treated as untrusted input.

## Usage

Copy `terraform.tfvars.example` to `terraform.tfvars`, fill in the runner values from Ona, and run:

```sh
terraform init
terraform plan
terraform apply
```

Development environments cannot reach SCMs, editor downloads, package registries, or arbitrary websites until their exact hostnames are added to `firewall_allowed_domains`. Cloud NGFW FQDN objects do not accept wildcard names. `firewall_allowed_ip_ranges` can add HTTPS CIDR exceptions when an endpoint does not have stable DNS.

Cloud NGFW FQDN rules alone resolve names to destination IP addresses. The example also uses Cloud NGFW URL filtering to distinguish an approved hostname from other services sharing the same destination IP.

The example always creates project-scoped Cloud NGFW Enterprise URL-filtering profiles and a billable firewall endpoint in every configured zone. Among hostname-based connections, only `firewall_allowed_domains` are allowed by the profile's SNI or HTTP host inspection; its implicit fallback denies other domains. Explicit `firewall_allowed_ip_ranges` bypass Layer 7 inspection. The rule targets the environment VM service account, leaving runner control-plane traffic on the FQDN path.

URL filtering relies on plaintext SNI or HTTP host information and does not decrypt TLS payloads. TLS decryption and packet capture are not created because both require customer-owned certificate or collector infrastructure that this module cannot choose safely.

These controls provide network and Google Cloud API evidence; they do not identify commands, file access, or process behavior inside the guest. That requires a protected host sensor or EDR that exports telemetry off the VM. Ona's management plane has no implicit access to logs in a customer project, so an explicit customer access grant is required for Ona-operated investigation.

The PSC endpoint IP must not overlap a VPC subnet, allocated range, or conflicting `/32` route. Change `psc_google_apis_ip` if `10.255.0.5` overlaps your network plan.

See the [Ona GCP access requirements](https://ona.com/docs/ona/runners/gcp/detailed-access-requirements), [Google APIs over PSC](https://cloud.google.com/vpc/docs/configure-private-service-connect-apis), [Cloud NGFW FQDN egress quickstart](https://cloud.google.com/firewall/docs/quickstarts/configure-nwfwpolicy-fqdn-egress), and [URL filtering overview](https://cloud.google.com/firewall/docs/about-url-filtering).
