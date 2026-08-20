# Security Policy

Report vulnerabilities privately through https://ona.com/security. Do not put credentials, customer data, or exploit evidence in public issues or pull requests.

This is security-review guidance for the Ona GCP Runner Terraform module. It defines intended boundaries and properties, not proof that every deployment satisfies them. The runtime binaries are maintained in the separate `gitpod-next` repository; follow the end-to-end path there when Terraform configuration, bootstrap data, or IAM grants depend on runtime behavior.

## System and Scope

This module deploys an Ona runner into a customer-controlled GCP project and VPC. Each development environment is a full Compute Engine VM where repository code, devcontainers, tools, and agents may execute. The environment VM is the default security boundary, not the checkout, devcontainer, Unix user, process, or conversation. Code running inside its assigned VM is expected to have broad VM-local control.

The main deployment contains:

| Surface | Role and source landmarks |
| --- | --- |
| Runner VM | A regional Managed Instance Group running the GCP orchestrator, auth-proxy, Prometheus, and node-exporter containers from `runner-vm.tf` and `files/runner-cloud-init.tftpl`. It is logically single-active; temporary overlap during rolling replacement is possible and must remain single-writer. |
| Proxy VMs | A separate regional Managed Instance Group running `gateway/proxy` plus monitoring containers from `proxy-vm.tf` and `files/proxy-cloud-init.tftpl`. It routes runner, HTTPS, WebSocket, SSH, and port traffic to the selected runner or environment VM. |
| Environment VMs | Compute Engine VMs created dynamically by the runner. Their startup script invokes the preinstalled `runner/gcp/environment-agent`, which downloads components, fetches the initial spec through auth-proxy, and starts Supervisor. |
| GCP state and credentials | Runner, environment, and proxy service accounts; Secret Manager secrets; Redis over Private Service Connect; GCS buckets; Artifact Registry; Pub/Sub; KMS; disks, snapshots, images, instance templates, and warm-pool MIGs. |
| Network edge | External or internal load balancer, proxy instances, firewall rules, DNS, certificates, and optional custom-domain/PSC infrastructure. External mode terminates TLS at the GCP SSL proxy; internal managed TCP-proxy mode passes TLS to `gateway/proxy`, which terminates it. |

Internal load-balancer deployments depend on correct customer VPC routing and regional managed-proxy subnet configuration. Treat external and internal load-balancer modes as distinct security surfaces.

Relevant companion code in `gitpod-next` includes `runner/gcp/orchestrator/`, `runner/gcp/environment-agent/`, `gateway/proxy/`, `runner/shared/runnerkit/`, and `runner/shared/supervisor/`. A scan’s explicit target remains authoritative, but do not infer an end-to-end control from only one repository when the boundary crosses both.

## Threat Model and Trust Boundaries

Trusted operators provide Terraform inputs and may deliberately supply pre-created service accounts, custom images and registry credentials, proxy settings, custom CAs, certificates, KMS keys, VPCs, and subnets. Treat those inputs as operator-controlled unless a realistic lower-privilege attacker can influence them. Do not assume externally managed IAM is safe merely because `pre_created_service_accounts.attach_iam_policies` is false.

Treat repository and devcontainer content, environment workloads, hostnames, ports, HTTP headers, WebSocket and SSH traffic, environment IDs, GCP labels and metadata, Redis state, Pub/Sub audit events, cached routing or VM state, component URLs, release manifests, custom registry images, bootstrap artifacts, certificates, trust bundles, Docker configuration, disks, snapshots, prebuilds, warm pools, logs, metrics, and status payloads as attacker-controlled whenever a realistic actor can influence them.

Important boundaries include:

- Client or customer-network traffic → load balancer → proxy VM → selected runner or environment VM.
- Environment VM → GCP metadata identity token → auth-proxy → Redis-backed initial spec.
- Runner VM and its service account → GCP Compute, Secret Manager, Storage, Artifact Registry, Pub/Sub, Logging, Monitoring, IAM, and KMS APIs.
- Environment, runner, and proxy service accounts → their distinct metadata credentials and IAM permissions.
- Management plane → runner token-authenticated control, status, release, and component-download flows.
- One environment VM, disk, snapshot, prebuild, or warm-pool instance → another environment or customer resource.
- Terraform plan/state and VM user-data → runtime files, containers, logs, and diagnostics.

## Privileged Flows to Trace

Deep scans should enumerate actual API calls and compare them with Terraform-granted permissions; this list is a starting map, not an exhaustive allowlist:

| Component | Security-relevant operations |
| --- | --- |
| Terraform deployer | Creates IAM, service accounts, firewall rules, load balancers, MIGs, Redis, Pub/Sub, buckets, registries, certificates, secrets, and cloud-init user-data. `local-exec` health validation also handles a deployer access token. |
| Runner daemon | Registers and reports to the management plane; reads release/component information; manages environment VMs, labels, metadata, service accounts, disks, snapshots, images, prebuilds, warm pools, instance templates, MIGs, autoscalers, Redis state, Secret Manager values, Artifact Registry, GCS, Pub/Sub, and telemetry. |
| Environment agent | Reads instance metadata, obtains a GCE identity token, downloads Supervisor/CLI/trust material, calls auth-proxy for the initial spec, writes Supervisor configuration, reports startup errors through labels/metadata, and shuts down on failure. |
| Auth-proxy | Verifies Google-signed GCE identity tokens and their issuer, audience, freshness, project, instance, labels, metadata, and network tag before returning an environment’s initial spec from Redis. |
| Gateway proxy | Resolves runner and environment VMs through Compute API labels plus network tags, terminates TLS when required, enforces port admission, strips proxy-consumed authorization material, and forwards only to the resolved internal target. |

## Security Invariants

- Arbitrary code inside an assigned environment VM is expected, but compromise of that VM must not expose peer environments, runner or proxy hosts, unrelated disks, snapshots, prebuilds, warm pools, caches, secrets, cloud identities, or customer network resources.
- Runner, environment, proxy, Terraform deployer, management-plane, and user identities must remain distinct, least-privileged, audience-bound, and non-interchangeable. The runner may `actAs` only the specific service accounts required for runner, proxy, and environment instances.
- The environment VM service account must not gain runner or proxy authority, read runner tokens or unrelated secrets, mutate fleet resources, or impersonate other service accounts. Metadata access is expected, but it must yield only the intended VM identity.
- Auth-proxy must fail closed unless a fresh Google-signed GCE identity token is bound to the expected audience and project, and current Compute metadata proves the calling VM is the requested environment with the required runner binding and environment network tag. Warm-pool relabeling, metadata updates, and cache invalidation must not permit stale or cross-environment spec access.
- Proxy routing must bind host, environment ID, runner ID, labels, tags, target IP, protocol, and port to the intended live VM. Ambiguous, stale, duplicate, malformed, or unauthorized routes must fail closed; port-auth tokens must remain environment-, port-, nonce-, issuer-, and audience-bound.
- Environment traffic must reach runner/auth-proxy services only through intended authenticated paths. Firewall tags, source ranges, health-check rules, IAP access, proxy egress, and internal/external load-balancer modes must not create an unintended environment-to-runner, environment-to-proxy, or public management path.
- TLS termination, certificate retrieval and rotation, trust-bundle installation, and custom-CA behavior must preserve endpoint identity in both load-balancer modes. A private address, internal load balancer, or VPC location is not authentication.
- Runner tokens, runner-secrets keys, Redis credentials, certificate private keys, Docker registry credentials, metrics credentials, and environment secrets must not leak through Terraform output, VM metadata, user-data, logs, metrics, traces, support artifacts, snapshots, prebuilds, or caches. Secret Manager use alone is not proof that plan, state, bootstrap, and logging paths are safe.
- Bootstrap and update inputs, including cloud-init, environment-agent, Supervisor/CLI URLs, runner/proxy images, custom registries, release manifests, instance templates, and trust bundles, must have authenticated provenance and integrity, resist replay or downgrade, and remain bound to the intended runner and deployment mode.
- Stop, delete, restart, replacement, recovery, prebuild, warm-pool claim, dual-disk, snapshot, and cross-zone flows must preserve ownership and lifecycle binding. Reused or recovered state must not retain another environment’s data, credentials, identity, routing, or authorization.
- Dual-disk and cross-zone restart are optional modes. When enabled, deletion, delayed snapshots, detached disks, recovery labels, zone fallback, and cleanup are security-relevant; when disabled, do not assume their controls exist.
- Temporary runner overlap during MIG rollouts must not allow two active writers to process lifecycle or update operations. Leader election, Redis state, retries, and rollback must fail safely under crash, partition, stale-lock, and mixed-version conditions.
- Pub/Sub, Cloud Logging, Redis, metrics, health, pprof, status, and diagnostic paths must treat payloads as untrusted, remain bounded, avoid secret disclosure, and not let one environment cause material shared availability or cloud-cost impact.

## Reportable Findings and Severity Context

Report a source-backed failure with a realistic attacker, reachable path, violated invariant, and meaningful additional impact. Relevant findings include environment-to-runner or cloud escalation, cross-environment or cross-customer access, initial-spec theft, proxy misrouting, port-admission bypass, service-account impersonation, credential disclosure or persistence, unsafe IAM or firewall defaults, bootstrap or update compromise, lifecycle data persistence, destructive cross-zone or cleanup behavior, and material shared availability or cloud-cost impact.

Calibrate severity to authority gained, data sensitivity, blast radius, deployment mode, prerequisites, persistence, exploitability, and effective controls:

- **Critical:** fleet-wide runner or release compromise, broadly trusted Terraform/deployment compromise, or widespread cross-customer secret or source access.
- **High:** runner/proxy/cloud-identity compromise, cross-environment sensitive disclosure or control, durable credential theft, or a reachable public/internal edge bypass with broad impact.
- **Medium:** bounded single-runner or single-tenant privilege expansion, conditional routing/admission bypass, lifecycle persistence, or meaningful authenticated shared-service impact.
- **Low:** narrow impact with strong prerequisites and no sensitive data or broader authority, such as a limited unauthorized state change.

State required IAM grants, network reachability, load-balancer mode, feature flags, custom-image or custom-CA settings, dual-disk/warm-pool/prebuild state, and runner/module versions. Do not treat optional controls, audit logs, private networking, feature flags, or undocumented external IAM as proof of safety.

## Out of Scope, Exclusions, and Accepted Risk

No vulnerability class, deployment mode, feature flag, or accepted risk is globally excluded.

Do not report solely that a user can execute code, modify files or processes, consume resources, or access explicitly granted secrets and destinations inside their assigned environment VM. Do not report same-environment denial of service or persistence of that environment’s own documented data without an additional boundary crossing, overbroad authority, substitution, replay, or bypass of an enabled control.

Operator-selected custom images, registries, CAs, proxy settings, pre-created service accounts, or insecure-registry settings are not findings by themselves. They remain reportable when module defaults, validation, generated configuration, documentation, or runtime behavior silently broadens authority, leaks secrets, disables an intended boundary, or creates a realistic attacker path.

## Known Limitations and Evidence

Repository source describes intended configuration, not deployed reality. It cannot prove the customer’s VPC routing, proxy-only subnet, DNS, firewall hierarchy, IAM grants for pre-created service accounts, organization policies, Secret Manager contents, certificate issuance, image mirroring, feature rollout, or deployed runner version. Record unresolved deployment assumptions instead of suppressing a finding.

Treat the Terraform module version, runner/proxy image version, and matching `gitpod-next` source as a versioned set. When behavior depends on `runner/gcp/orchestrator`, `runner/gcp/environment-agent`, `gateway/proxy`, Supervisor, or management-plane APIs, inspect the corresponding source or explicitly mark the cross-repository evidence gap.

References: [README](README.md), [IAM reference](docs/detailed_iam_reference.md), [runner VM](runner-vm.tf), [proxy VM](proxy-vm.tf), [load balancer](loadbalancer.tf), [firewall rules](firewall.tf), [runner bootstrap](files/runner-cloud-init.tftpl), and [proxy bootstrap](files/proxy-cloud-init.tftpl).
