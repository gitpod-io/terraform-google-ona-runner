provider "google" {
  project      = "runner-project"
  access_token = "unused-plan-test-token"
}

provider "google-beta" {
  project      = "runner-project"
  access_token = "unused-plan-test-token"
}

override_module {
  target = module.runner
  outputs = {
    environment_vm_service_account_email = "test-runner-env-vm@runner-project.iam.gserviceaccount.com"
    internal_runner_ips                  = ["10.0.0.10", "10.0.0.11"]
    internal_runner_hostname             = "runner.ona-00000000-0000-4000-8000-000000000001.internal"
  }
}

variables {
  project_id   = "runner-project"
  region       = "us-central1"
  zones        = ["us-central1-a", "us-central1-b"]
  runner_id    = "00000000-0000-4000-8000-000000000001"
  runner_token = "test-token"
  runner_name  = "test-runner"
}

run "default_deny_with_private_google_apis" {
  command = plan

  assert {
    condition = (
      google_compute_network.runner.network_firewall_policy_enforcement_order == "BEFORE_CLASSIC_FIREWALL" &&
      google_compute_subnetwork.runner.private_ip_google_access &&
      google_compute_subnetwork.runner.log_config[0].aggregation_interval == "INTERVAL_5_SEC" &&
      google_compute_subnetwork.runner.log_config[0].flow_sampling == 1 &&
      google_compute_subnetwork.runner.log_config[0].metadata == "INCLUDE_ALL_METADATA" &&
      google_compute_router_nat.egress.source_subnetwork_ip_ranges_to_nat == "LIST_OF_SUBNETWORKS" &&
      google_compute_router_nat.egress.log_config[0].enable &&
      google_compute_router_nat.egress.log_config[0].filter == "ALL"
    )
    error_message = "The VPC must evaluate Cloud NGFW first and retain private Google access plus Cloud NAT."
  }

  assert {
    condition = (
      google_dns_policy.query_logging.enable_logging &&
      length(google_dns_policy.query_logging.networks) == 1
    )
    error_message = "Cloud DNS query logging must cover the restricted runner VPC."
  }

  assert {
    condition = (
      google_compute_global_address.google_apis.address == "10.255.0.5" &&
      google_compute_global_address.google_apis.purpose == "PRIVATE_SERVICE_CONNECT" &&
      google_compute_global_forwarding_rule.google_apis.target == "all-apis" &&
      google_compute_global_forwarding_rule.google_apis.load_balancing_scheme == ""
    )
    error_message = "Google APIs must use the all-apis Private Service Connect endpoint."
  }

  assert {
    condition = (
      toset(keys(google_dns_managed_zone.google_apis)) == toset(["gcr.io", "googleapis.com", "pkg.dev"]) &&
      alltrue([
        for domain, zone in google_dns_managed_zone.google_apis :
        zone.visibility == "private" && zone.dns_name == "${domain}."
      ]) &&
      alltrue([
        for domain, record in google_dns_record_set.google_apis_wildcard :
        record.name == "*.${domain}." && one(record.rrdatas) == "${domain}."
      ])
    )
    error_message = "Google API and registry hostnames must resolve privately to PSC."
  }

  assert {
    condition = (
      google_compute_network_firewall_policy_rule.internal.action == "goto_next" &&
      google_compute_network_firewall_policy_rule.google_apis_psc.action == "goto_next" &&
      google_compute_network_firewall_policy_rule.allowed_domains.action == "goto_next" &&
      toset(one(google_compute_network_firewall_policy_rule.allowed_domains.match).dest_fqdns) == toset(["app.gitpod.io"]) &&
      toset(one(one(google_compute_network_firewall_policy_rule.allowed_domains.match).layer4_configs).ports) == toset(["443"]) &&
      length(google_compute_network_firewall_policy_rule.allowed_ip_ranges) == 0 &&
      google_compute_network_firewall_policy_rule.deny_all.action == "deny" &&
      google_compute_network_firewall_policy_rule.deny_all.enable_logging &&
      google_compute_network_firewall_policy_rule.deny_all.priority == 65000
    )
    error_message = "The default policy must allow only internal, PSC, and app.gitpod.io HTTPS before denying all other egress."
  }


  assert {
    condition = (
      google_logging_project_bucket_config.security_archive.retention_days == 90 &&
      google_logging_project_bucket_config.security_archive.enable_analytics &&
      !google_logging_project_bucket_config.security_archive.locked &&
      google_logging_project_bucket_config.security_archive.deletion_policy == "DELETE" &&
      strcontains(google_logging_project_sink.security_archive.filter, "dns.googleapis.com/dns_queries") &&
      strcontains(google_logging_project_sink.security_archive.filter, "compute.googleapis.com/vpc_flows") &&
      length(google_logging_project_sink.security_export) == 0
    )
    error_message = "Security logs must be routed to a dedicated 90-day analytics bucket by default."
  }

  assert {
    condition = (
      toset(keys(google_project_iam_audit_config.extended)) == toset([
        "artifactregistry.googleapis.com",
        "cloudkms.googleapis.com",
        "logging.googleapis.com",
        "monitoring.googleapis.com",
      ]) &&
      length(google_monitoring_alert_policy.denied_egress) == 1 &&
      length(google_monitoring_alert_policy.environment_api_denied) == 1 &&
      length(google_monitoring_alert_policy.security_control_change) == 1 &&
      length(google_monitoring_alert_policy.dns_nxdomain) == 1 &&
      length(google_monitoring_alert_policy.inspection_fallback) == 0 &&
      length(google_logging_metric.dns_nxdomain) == 1
    )
    error_message = "Extended API auditing and baseline security alerts must be enabled by default."
  }

  assert {
    condition = (
      length(google_network_security_security_profile.url_filtering) == 0 &&
      length(google_compute_network_firewall_policy_rule.url_filtering) == 0 &&
      length(google_compute_packet_mirroring.environment) == 0
    )
    error_message = "Billable deep inspection and packet mirroring must remain opt-in."
  }

  assert {
    condition = (
      toset(output.firewall_allowed_domains) == toset(["app.gitpod.io"]) &&
      toset(output.internal_runner_ips) == toset(["10.0.0.10", "10.0.0.11"])
    )
    error_message = "The example outputs must expose the effective public allowlist and restricted runner addresses."
  }
}

run "disables_optional_audit_and_alerts" {
  command = plan

  variables {
    enable_extended_audit_logs = false
    enable_security_alerts     = false
  }

  assert {
    condition = (
      length(google_project_iam_audit_config.extended) == 0 &&
      length(google_logging_metric.dns_nxdomain) == 0 &&
      length(google_monitoring_alert_policy.denied_egress) == 0 &&
      length(google_monitoring_alert_policy.environment_api_denied) == 0 &&
      length(google_monitoring_alert_policy.security_control_change) == 0 &&
      length(google_monitoring_alert_policy.dns_nxdomain) == 0 &&
      length(google_monitoring_alert_policy.inspection_fallback) == 0
    )
    error_message = "Disabling optional audit coverage and alerts must omit their resources, including the alert-only log metric."
  }
}

run "locked_archive_with_external_export" {
  command = plan

  variables {
    lock_security_log_bucket = true
    security_log_export_destinations = {
      siem = "pubsub.googleapis.com/projects/security-project/topics/runner-events"
    }
  }

  assert {
    condition = (
      google_logging_project_bucket_config.security_archive.locked &&
      google_logging_project_bucket_config.security_archive.deletion_policy == "ABANDON" &&
      toset(keys(google_logging_project_sink.security_export)) == toset(["siem"]) &&
      contains(keys(output.security_log_export_writer_identities), "siem")
    )
    error_message = "Locked archives must survive destroy and external sinks must expose their writer identities."
  }
}

run "deep_inspection_integrations" {
  command = plan

  variables {
    enable_url_filtering                       = true
    firewall_allowed_ip_ranges                 = ["203.0.113.10/32"]
    url_filtering_tls_inspection_policy        = "https://networksecurity.googleapis.com/v1/projects/runner-project/locations/us-central1/tlsInspectionPolicies/runner-egress"
    packet_mirroring_collector_forwarding_rule = "https://www.googleapis.com/compute/v1/projects/runner-project/regions/us-central1/forwardingRules/packet-collector"
  }

  assert {
    condition = (
      length(google_network_security_security_profile.url_filtering) == 1 &&
      toset(one(one(google_network_security_security_profile.url_filtering[0].url_filtering_profile).url_filters).urls) == toset(["app.gitpod.io"]) &&
      length(google_network_security_security_profile_group.url_filtering) == 1 &&
      toset(keys(google_network_security_firewall_endpoint.url_filtering)) == toset(["us-central1-a", "us-central1-b"])
    )
    error_message = "URL filtering must deploy the approved domain profile and an endpoint in every configured zone."
  }

  assert {
    condition = (
      google_compute_network_firewall_policy_rule.url_filtering[0].action == "apply_security_profile_group" &&
      google_compute_network_firewall_policy_rule.url_filtering[0].enable_logging &&
      google_compute_network_firewall_policy_rule.url_filtering[0].tls_inspect &&
      toset(google_compute_network_firewall_policy_rule.url_filtering[0].target_service_accounts) == toset(["test-runner-env-vm@runner-project.iam.gserviceaccount.com"]) &&
      google_compute_network_firewall_policy_rule.url_filtering_allowed_ip_ranges[0].priority == 225 &&
      toset(one(google_compute_network_firewall_policy_rule.url_filtering_allowed_ip_ranges[0].match).dest_ip_ranges) == toset(["203.0.113.10/32"]) &&
      alltrue([
        for association in google_network_security_firewall_endpoint_association.url_filtering :
        association.tls_inspection_policy == "https://networksecurity.googleapis.com/v1/projects/runner-project/locations/us-central1/tlsInspectionPolicies/runner-egress"
      ])
    )
    error_message = "Environment HTTPS must use the URL profile and optional TLS policy without affecting the runner identity."
  }

  assert {
    condition = (
      length(google_compute_packet_mirroring.environment) == 1 &&
      toset(one(google_compute_packet_mirroring.environment[0].mirrored_resources).tags) == toset(["gitpod-type-environment"]) &&
      one(google_compute_packet_mirroring.environment[0].filter).direction == "BOTH"
    )
    error_message = "Packet mirroring must target only environment-tagged VM traffic in both directions."
  }
}

run "rejects_tls_policy_without_url_filtering" {
  command = plan

  variables {
    url_filtering_tls_inspection_policy = "https://networksecurity.googleapis.com/v1/projects/runner-project/locations/us-central1/tlsInspectionPolicies/runner-egress"
  }

  expect_failures = [var.url_filtering_tls_inspection_policy]
}

run "rejects_tls_policy_in_another_region" {
  command = plan

  variables {
    enable_url_filtering                = true
    url_filtering_tls_inspection_policy = "https://networksecurity.googleapis.com/v1/projects/runner-project/locations/us-east1/tlsInspectionPolicies/runner-egress"
  }

  expect_failures = [var.url_filtering_tls_inspection_policy]
}

run "rejects_packet_collector_in_another_region" {
  command = plan

  variables {
    packet_mirroring_collector_forwarding_rule = "https://www.googleapis.com/compute/v1/projects/runner-project/regions/us-east1/forwardingRules/packet-collector"
  }

  expect_failures = [var.packet_mirroring_collector_forwarding_rule]
}

run "extended_allowlist" {
  command = plan

  variables {
    firewall_allowed_domains   = ["app.gitpod.io", "github.com"]
    firewall_allowed_ip_ranges = ["192.0.2.0/24"]
  }

  assert {
    condition = (
      toset(one(google_compute_network_firewall_policy_rule.allowed_domains.match).dest_fqdns) == toset(["app.gitpod.io", "github.com"]) &&
      length(google_compute_network_firewall_policy_rule.allowed_ip_ranges) == 1 &&
      toset(one(google_compute_network_firewall_policy_rule.allowed_ip_ranges[0].match).dest_ip_ranges) == toset(["192.0.2.0/24"])
    )
    error_message = "Operators must be able to extend the HTTPS domain and CIDR allowlists."
  }
}

run "normalizes_domains" {
  command = plan

  variables {
    firewall_allowed_domains = ["APP.GITPOD.IO", "app.gitpod.io"]
  }

  assert {
    condition     = toset(one(google_compute_network_firewall_policy_rule.allowed_domains.match).dest_fqdns) == toset(["app.gitpod.io"])
    error_message = "FQDN allowlist entries must be lowercase and deduplicated."
  }
}

run "limits_psc_endpoint_name" {
  command = plan

  variables {
    runner_name = "restricted-runner-with-a-long-name"
  }

  assert {
    condition     = length(google_compute_global_forwarding_rule.google_apis.name) <= 20
    error_message = "The PSC forwarding rule name must not exceed Google's 20-character endpoint limit."
  }
}
