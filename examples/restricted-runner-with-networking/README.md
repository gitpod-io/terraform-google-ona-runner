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

These records are routed to a dedicated Log Analytics bucket with 90-day retention by default. Environment VM names contain the Ona environment ID, which provides direct attribution in DNS, firewall, flow, and NAT records. Google API audit records identify the shared environment VM service account, not an individual environment. Correlate audit timestamps and caller IPs with the network records; concurrent activity can remain ambiguous.

High-volume VPC Flow Logs and Data Access audit logs incur Cloud Logging ingestion and retention costs. Size retention and downstream exports for the expected adversarial workload before enabling a locked archive.

Set `lock_security_log_bucket = true` only after validating retention and data-residency requirements. Locking is irreversible. Terraform abandons a locked bucket during destroy so its retained evidence is not deleted.

`security_log_export_destinations` creates additional sinks for a customer security project, Cloud Storage archive, BigQuery dataset, or Pub/Sub SIEM stream. After apply, grant every identity in the `security_log_export_writer_identities` output permission to write to its destination. A cross-project destination is required when operators must retain evidence independently of administrators in the runner project.

Cloud Monitoring policies alert on denied egress, denied environment API calls, restricted-runner security-control changes, unusual NXDOMAIN volume, and Cloud NGFW inspection fail-open events. Set `security_notification_channels` to deliver the incidents to an existing response system. Security Command Center Event Threat Detection can additionally analyze the DNS, NAT, firewall, and flow logs when it is activated for the project or organization.

Cloud-generated records are the forensic source of truth. The environment VM service account can write application logs and metrics, so guest-authored telemetry must be treated as untrusted input.

## Usage

Copy `terraform.tfvars.example` to `terraform.tfvars`, fill in the runner values from Ona, and run:

```sh
terraform init
terraform plan
terraform apply
```

Development environments cannot reach SCMs, editor downloads, package registries, or arbitrary websites until their exact hostnames are added to `firewall_allowed_domains`. Cloud NGFW FQDN objects do not accept wildcard names. `firewall_allowed_ip_ranges` can add HTTPS CIDR exceptions when an endpoint does not have stable DNS.

Cloud NGFW resolves FQDN objects to destination IP addresses; it does not inspect TLS SNI or URLs. Use Cloud NGFW URL filtering and TLS inspection if workloads must distinguish an approved hostname from other services sharing the same destination IP.

Set `enable_url_filtering = true` to create project-scoped Cloud NGFW Enterprise URL-filtering profiles and a billable firewall endpoint in every configured zone. Among hostname-based connections, only `firewall_allowed_domains` are allowed by the profile's SNI or HTTP host inspection; its implicit fallback denies other domains. Explicit `firewall_allowed_ip_ranges` bypass Layer 7 inspection. The rule targets the environment VM service account, leaving runner control-plane traffic on the FQDN path.

URL filtering without TLS inspection relies on plaintext SNI and cannot inspect encrypted headers. To enable decryption, provide an existing `url_filtering_tls_inspection_policy` and install its issuing CA in environment clients. Certificate pinning and protocols unsupported by Cloud NGFW can fail when inspection is enabled.

Set `packet_mirroring_collector_forwarding_rule` to an operator-managed regional internal forwarding rule configured as a mirroring collector in the runner region and VPC. The example then mirrors ingress and egress packets for instances tagged `gitpod-type-environment`. Mirroring adds bandwidth and collector costs, and application-layer encryption remains encrypted unless TLS is intercepted.

These controls provide network and Google Cloud API evidence; they do not identify commands, file access, or process behavior inside the guest. That requires a protected host sensor or EDR that exports telemetry off the VM. Ona's management plane has no implicit access to logs in a customer project, so cross-project export or an explicit customer access grant is required for Ona-operated investigation.

The PSC endpoint IP must not overlap a VPC subnet, allocated range, or conflicting `/32` route. Change `psc_google_apis_ip` if `10.255.0.5` overlaps your network plan.

See the [Ona GCP access requirements](https://ona.com/docs/ona/runners/gcp/detailed-access-requirements), [Google APIs over PSC](https://cloud.google.com/vpc/docs/configure-private-service-connect-apis), [Cloud NGFW FQDN egress quickstart](https://cloud.google.com/firewall/docs/quickstarts/configure-nwfwpolicy-fqdn-egress), [URL filtering overview](https://cloud.google.com/firewall/docs/about-url-filtering), and [Packet Mirroring overview](https://cloud.google.com/vpc/docs/packet-mirroring).
