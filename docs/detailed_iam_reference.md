# Ona GCP Runner - Permissions and Scopes Documentation

This document provides a comprehensive overview of all IAM permissions, OAuth scopes, and security configurations used by the Ona GCP Runner Terraform module.

## Overview

The module creates a secure, least-privilege infrastructure for running Ona workspaces on Google Cloud Platform. It uses multiple service accounts with specific roles and OAuth scopes to ensure proper isolation and security.

## Service Accounts

**Architecture Rationale**: Ona uses multiple specialized service accounts instead of a single account to implement defense-in-depth security:

- **Blast Radius Limitation**: If one service account is compromised, damage is limited to its specific function
- **Principle of Least Privilege**: Each account has only the minimum permissions needed for its role
- **Audit Granularity**: Security events can be traced to specific functions (e.g., secret access vs. VM creation)
- **Operational Isolation**: Different operational concerns (compute, storage, secrets) are separated
- **Compliance**: Easier to demonstrate security controls to auditors with clear separation of duties

### 1. Runner Service Account (`runner`)
**Purpose**: Manages the runner infrastructure and orchestrates workspace lifecycle

**Display Name**: Ona Runner  
**Account ID**: `{runner_name}-runner`  
**Description**: Service account for runner infrastructure management

**OAuth Scopes**:
- `https://www.googleapis.com/auth/logging.write` - Write access to Cloud Logging for centralized workspace logs
- `https://www.googleapis.com/auth/monitoring.write` - Write access to Cloud Monitoring for workspace metrics and health checks
- `https://www.googleapis.com/auth/compute` - **Full access to Compute Engine** (required for dynamic VM lifecycle management: create, delete, start, stop, modify instances and disks)
- `https://www.googleapis.com/auth/devstorage.read_write` - **Read/write access to Cloud Storage** (required for build cache uploads, workspace persistence, and container image management)
- `https://www.googleapis.com/auth/pubsub` - Full access to Pub/Sub for event-driven workspace reconciliation and scaling
- `https://www.googleapis.com/auth/cloud-platform` - **Access to additional Google Cloud services** (see detailed justification below)

**Why `cloud-platform` scope is needed** (Security Note: This broad scope is required because specific OAuth scopes don't exist for these critical services):
- **IAM Credentials API**: Generate short-lived access tokens for other service accounts (enables secure impersonation pattern)
- **Service Networking API**: Manage VPC peering for Redis (required for workspace session storage)
- **Redis API**: Create and manage Redis instances (required for workspace state and session management)
- **Secret Manager API**: Access Redis authentication credentials and runner tokens
- **Artifact Registry API**: Manage container image repositories for workspace images

**Security Mitigation**: While `cloud-platform` is broad, access is limited by IAM permissions. The runner's custom IAM role restricts actual capabilities to only necessary operations.

**IAM Roles**:
- **Custom Role**: `{runner_name}_runner` - Minimal permissions for infrastructure management (detailed below)
- `roles/logging.logWriter` - Write access to Cloud Logging for operational logs
- `roles/monitoring.metricWriter` - Write access to Cloud Monitoring for metrics and health data
- `roles/cloudtrace.agent` - Write access to Cloud Trace for distributed tracing
- `roles/redis.editor` - Manage Redis instances for workspace state storage (not admin - cannot manage instance lifecycle, only read/write data)

**Security Note**: The runner uses minimal writer/editor roles instead of admin roles. It cannot create logging sinks, monitoring dashboards, or pub/sub infrastructure - these are managed by Terraform. This reduces the blast radius if the service account is compromised.

### 2. Environment VM Service Account (`environment_vm`)
**Purpose**: Used by workspace VMs for accessing workspace-specific resources

**Display Name**: Ona Environment VM  
**Account ID**: `{runner_name}-env-vm`  
**Description**: Minimal service account for environment VMs

**OAuth Scopes**: None (uses IAM permissions only)

**IAM Roles**:
- `roles/monitoring.metricWriter` - Write custom metrics for workspace monitoring (CPU, memory, disk usage, application-specific metrics)
- `roles/logging.logWriter` - Write logs to Cloud Logging for workspace activity and debugging
- `roles/artifactregistry.reader` - Read container images from Artifact Registry for workspace setup

**Security Rationale**: Workspace VMs have minimal permissions - only metric writing, logging, and reading container images. No access to other workspaces, secrets, or infrastructure management. This limits blast radius if a workspace is compromised.

### 3. Build Cache Service Account (`build_cache`)
**Purpose**: Manages build cache storage and access

**Display Name**: Ona Build Cache  
**Account ID**: `{runner_name}-build-cache`  
**Description**: Service account for GCS build cache operations

**OAuth Scopes**: None (uses IAM permissions only)

**IAM Roles**:
- `roles/storage.objectAdmin` - Manage build cache objects in Cloud Storage (upload, download, delete cached build artifacts and container layers)
- `roles/logging.logWriter` - Write logs to Cloud Logging for cache operation auditing

**Security Rationale**: Isolated service account prevents workspace VMs from accessing build cache directly. Runner impersonates this account only when cache operations are needed, providing controlled access and audit trail.

### 4. Secret Manager Service Account (`secret_manager`)
**Purpose**: Manages workspace secrets and environment variables

**Display Name**: Ona Secret Manager  
**Account ID**: `{runner_name}-secrets`  
**Description**: Service account for environment secret management

**OAuth Scopes**: None (uses IAM permissions only)

**IAM Roles**:
- **Custom Role**: `{runner_name}_secret_manager` - Scoped permissions for secret management:
  - `secretmanager.secrets.create` - Create new workspace secrets
  - `secretmanager.secrets.delete` - Delete unused secrets
  - `secretmanager.secrets.get` - Get secret metadata
  - `secretmanager.secrets.list` - List secrets for management
  - `secretmanager.versions.access` - Access secret values
  - `secretmanager.versions.add` - Add new secret versions
  - `secretmanager.versions.destroy` - Delete secret versions
- `roles/logging.logWriter` - Write logs to Cloud Logging for secret operation auditing

**Security Rationale**: Dedicated service account for secret operations with minimal custom permissions (no IAM policy management). Secrets are isolated per workspace. Runner impersonates this account only during secret operations, ensuring secrets are never directly accessible to workspace VMs.

### 5. Pub/Sub Processor Service Account (`pubsub_processor`)
**Purpose**: Processes Pub/Sub messages for event-driven operations

**Display Name**: Ona Pub/Sub Processor  
**Account ID**: `{runner_name}-pubsub`  
**Description**: Service account for processing Pub/Sub compute events

**OAuth Scopes**: None (uses IAM permissions only)

**IAM Roles**:
- `roles/monitoring.metricWriter` - Write processing metrics for monitoring (message processing rates, queue depths, error rates)
- `roles/logging.logWriter` - Write logs to Cloud Logging for event processing auditing

**Security Rationale**: Separate service account for async message processing provides isolation from synchronous operations. Limited to metric writing and logging only - no access to compute resources or secrets. The runner service account can impersonate this account for event processing operations.

### 6. Proxy VM Service Account (`proxy_vm`)
**Purpose**: Used by proxy VMs for load balancing and traffic routing

**Display Name**: Ona Proxy VM Service  
**Account ID**: `{runner_name}-proxy-vm`  
**Description**: Service account for Ona proxy VM instances

**OAuth Scopes**:
- `https://www.googleapis.com/auth/logging.write` - Write access to Cloud Logging for proxy access logs and error reporting
- `https://www.googleapis.com/auth/monitoring.write` - Write access to Cloud Monitoring for proxy health metrics and performance data
- `https://www.googleapis.com/auth/compute.readonly` - **Read-only access to Compute Engine** (required to discover workspace VMs for load balancing)
- `https://www.googleapis.com/auth/devstorage.read_only` - **Read-only access to Cloud Storage** (required to serve static assets and workspace files)

**IAM Roles**:
- `roles/logging.logWriter` - Write logs to Cloud Logging (access logs, error logs, security events)
- `roles/monitoring.metricWriter` - Write metrics to Cloud Monitoring (request rates, latency, error rates)
- **Custom Role**: `{runner_name}_proxy_vm` - Minimal compute permissions for service discovery:
  - `compute.instances.get` - Get instance details for routing
  - `compute.instances.list` - List instances for service discovery
  - `compute.networks.get` - Get network information for proxy functionality
  - `compute.subnetworks.get` - Get subnet information for routing
  - `compute.zones.get` - Get zone information for location awareness
  - `compute.regions.get` - Get region information for location awareness
  - `compute.projects.get` - Get project information for service discovery
- `roles/artifactregistry.reader` - Read container images from Artifact Registry (pull proxy container images for updates)
- `roles/run.viewer` - Read-only access to Cloud Run services (for service discovery)

**Security Rationale**: Proxy VMs have minimal read-only access to infrastructure for service discovery and content serving. Custom role provides only essential compute permissions instead of broad viewer access. No write access to compute or storage prevents proxies from modifying infrastructure.

## Custom IAM Role: Ona Runner

The runner service account uses a custom IAM role with minimal required permissions:

### Compute Engine Permissions

**Instance Lifecycle Management**:
- `compute.instances.create` - Create new workspace VMs
- `compute.instances.delete` - Delete terminated workspace VMs
- `compute.instances.get` - Get instance details
- `compute.instances.list` - List instances for monitoring
- `compute.instances.start` - Start stopped instances
- `compute.instances.stop` - Stop running instances
- `compute.instances.setLabels` - Set labels for resource management
- `compute.instances.setMetadata` - Configure instance metadata
- `compute.instances.setTags` - Set network tags for firewall rules
- `compute.instances.attachDisk` - Attach persistent disks
- `compute.instances.detachDisk` - Detach persistent disks
- `compute.instances.setDiskAutoDelete` - Configure disk auto-deletion
- `compute.instances.setServiceAccount` - Assign service accounts to VMs

**Disk Management**:
- `compute.disks.create` - Create persistent disks for workspaces
- `compute.disks.delete` - Delete unused persistent disks
- `compute.disks.get` - Get disk information
- `compute.disks.list` - List disks for management

**Network Resources**:
- `compute.networks.get` - Get network configuration
- `compute.networks.list` - List available networks
- `compute.networks.use` - Use networks for VM creation
- `compute.subnetworks.get` - Get subnet configuration
- `compute.subnetworks.list` - List available subnets
- `compute.subnetworks.use` - Use subnets for VM creation
- `compute.addresses.create` - Create static IP addresses
- `compute.addresses.delete` - Delete unused IP addresses
- `compute.addresses.get` - Get IP address information
- `compute.addresses.use` - Assign IP addresses to VMs

**Operations Monitoring**:
- `compute.globalOperations.get` - Monitor global operations
- `compute.regionOperations.get` - Monitor regional operations
- `compute.zoneOperations.get` - Monitor zonal operations

**Resource Information**:
- `compute.machineTypes.get` - Get machine type details
- `compute.machineTypes.list` - List available machine types
- `compute.diskTypes.get` - Get disk type information
- `compute.diskTypes.list` - List available disk types
- `compute.images.get` - Get VM image details
- `compute.images.list` - List available images
- `compute.images.useReadOnly` - Use images for VM creation

**Instance Templates and Groups**:
- `compute.instanceTemplates.create` - Create instance templates
- `compute.instanceTemplates.delete` - Delete instance templates
- `compute.instanceTemplates.get` - Get template information
- `compute.instanceTemplates.getIamPolicy` - Get template IAM policies
- `compute.instanceTemplates.list` - List instance templates
- `compute.instanceTemplates.setIamPolicy` - Set template IAM policies
- `compute.instanceTemplates.useReadOnly` - Use templates for VM creation
- `compute.instanceGroupManagers.get` - Get instance group details
- `compute.instanceGroupManagers.list` - List instance groups
- `compute.instanceGroupManagers.create` - Create instance groups
- `compute.instanceGroupManagers.delete` - Delete instance groups
- `compute.instanceGroupManagers.update` - Update instance groups
- `compute.instanceGroups.delete` - Delete underlying instance groups (required when deleting MIGs)
- `compute.instanceGroups.list` - List instance group members

### Cloud Logging Permissions

**Log Persistence for Environments and Prebuilds**:
- `logging.logEntries.list` - Read environment logs from Cloud Logging for prebuild creation
- `logging.logEntries.create` - Write prebuild logs to Cloud Logging for persistence
- `logging.logs.delete` - Delete prebuild logs when prebuild is deleted to prevent orphaned data

### Artifact Registry Permissions

**Repository Management**:
- `artifactregistry.repositories.get` - Get repository information
- `artifactregistry.repositories.list` - List repositories
- `artifactregistry.repositories.create` - Create repositories for image cache
- `artifactregistry.repositories.delete` - Delete unused repositories
- `artifactregistry.repositories.update` - Update repository configuration

**Image Management**:
- `artifactregistry.dockerimages.get` - Get Docker image information
- `artifactregistry.dockerimages.list` - List Docker images
- `artifactregistry.repositories.downloadArtifacts` - Download container images
- `artifactregistry.repositories.uploadArtifacts` - Upload container images

### Secret Manager Permissions

**Secret Management**:
- `secretmanager.secrets.create` - Create workspace secrets
- `secretmanager.secrets.delete` - Delete unused secrets
- `secretmanager.secrets.get` - Get secret metadata
- `secretmanager.secrets.list` - List secrets
- `secretmanager.secrets.getIamPolicy` - Get secret IAM policies
- `secretmanager.secrets.setIamPolicy` - Set secret IAM policies
- `secretmanager.versions.access` - Access secret values
- `secretmanager.versions.add` - Add new secret versions
- `secretmanager.versions.destroy` - Delete secret versions

### Pub/Sub Permissions

**Message Processing**:
- `pubsub.subscriptions.get` - Get subscription information
- `pubsub.subscriptions.list` - List subscriptions
- `pubsub.subscriptions.consume` - Consume messages from subscriptions
- `pubsub.topics.get` - Get topic information
- `pubsub.topics.list` - List topics

### IAM Permissions

**Service Account Management**:
- `iam.serviceAccounts.actAs` - Impersonate other service accounts
- `iam.serviceAccounts.getIamPolicy` - Get service account IAM policies
- `iam.serviceAccounts.setIamPolicy` - Set service account IAM policies
- `iam.serviceAccounts.getAccessToken` - Generate access tokens


## Service Account Impersonation and Usage

**Security Pattern**: The runner uses service account impersonation and controlled usage instead of direct permissions to enhance security and auditability.

**Why Impersonation/Usage Instead of Direct Permissions**:
- **Temporal Access Control**: Tokens are generated only when needed and have short lifespans (1 hour max)
- **Audit Trail**: Every impersonation/usage event is logged, providing clear audit trail of when and why privileged operations occurred
- **Credential Rotation**: No long-lived credentials stored on VMs - tokens are generated on-demand
- **Scope Limitation**: Each impersonated token has only the permissions of the target service account
- **Revocation**: Impersonation can be revoked instantly by removing TokenCreator/User roles

The runner service account can impersonate or use other service accounts for specific operations:

### Build Cache Token Generation
- **Target**: `build_cache` service account
- **Role**: `roles/iam.serviceAccountTokenCreator`
- **Purpose**: Generate short-lived tokens for build cache operations (upload/download artifacts)
- **Security Benefit**: Build cache access is logged and time-limited

### Secret Manager Token Generation
- **Target**: `secret_manager` service account
- **Role**: `roles/iam.serviceAccountTokenCreator`
- **Purpose**: Generate short-lived tokens for secret management operations (create/read workspace secrets)
- **Security Benefit**: Secret access is logged and time-limited, preventing credential theft

### Pub/Sub Processor Service Account Usage
- **Target**: `pubsub_processor` service account
- **Role**: `roles/iam.serviceAccountUser`
- **Purpose**: Use the pub/sub processor service account for event handling operations
- **Security Benefit**: Event processing is isolated and auditable through separate service account

## Audit Logging Configuration

Comprehensive audit logging is enabled for security monitoring:

### Secret Manager Audit Logging
- **Service**: `secretmanager.googleapis.com`
- **Log Types**: 
  - `DATA_READ` - Logs secret access (no exemptions)
  - `DATA_WRITE` - Logs secret creation/updates
  - `ADMIN_READ` - Logs metadata access

### Compute Engine Audit Logging
- **Service**: `compute.googleapis.com`
- **Log Types**:
  - `ADMIN_READ` - Logs administrative read operations
  - `DATA_WRITE` - Logs data modification operations

### IAM Audit Logging
- **Service**: `iam.googleapis.com`
- **Log Types**:
  - `ADMIN_READ` - Logs IAM policy reads
  - `DATA_WRITE` - Logs IAM policy changes

### Storage Audit Logging
- **Service**: `storage.googleapis.com`
- **Log Types**:
  - `DATA_READ` - Logs storage access (exempts environment VM service account for performance)
  - `DATA_WRITE` - Logs storage modifications
- **Exemptions**: `{runner_name}-env-vm@{project_id}.iam.gserviceaccount.com` (for performance - workspace file access generates high log volume)

## Security Considerations

### Principle of Least Privilege
- Each service account has only the minimum permissions required for its function
- OAuth scopes are restricted to necessary services
- Custom IAM roles limit permissions to specific operations instead of using broad predefined roles
- No service account has admin-level permissions except where absolutely necessary

### Network Security
- Firewall rules are managed via Terraform (no dynamic firewall permissions granted to service accounts)
- VMs use private IP addresses where possible
- Redis uses private service access with VPC peering
- Load balancer provides controlled external access with health checks

### Secret Management
- Workspace secrets are isolated using dedicated service account with custom minimal permissions
- Secret access is fully audited with no exemptions
- Runner token and Redis credentials are stored in Secret Manager
- Secrets are automatically cleaned up when workspaces are deleted

### Service Account Isolation
- Multiple specialized service accounts instead of one powerful account
- Service account impersonation provides temporal access control
- Each service account is limited to its specific operational domain
- Cross-service access is explicitly controlled through IAM bindings

### Monitoring and Auditing
- Comprehensive audit logging for all critical services (Secret Manager, Compute, IAM, Storage)
- Service account impersonation and usage is tracked
- Resource access patterns can be analyzed for anomaly detection
- Centralized logging with structured filters for security events

This permission model balances security with functionality, ensuring Ona can operate effectively while maintaining strong isolation, auditability, and defense-in-depth security controls.
