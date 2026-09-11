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
    internal_runner_ips      = ["10.0.0.10", "10.0.0.11"]
    internal_runner_hostname = "runner.ona-00000000-0000-4000-8000-000000000001.internal"
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
      google_compute_router_nat.egress.source_subnetwork_ip_ranges_to_nat == "LIST_OF_SUBNETWORKS"
    )
    error_message = "The VPC must evaluate Cloud NGFW first and retain private Google access plus Cloud NAT."
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
      google_compute_network_firewall_policy_rule.deny_all.priority == 65000
    )
    error_message = "The default policy must allow only internal, PSC, and app.gitpod.io HTTPS before denying all other egress."
  }

  assert {
    condition = (
      toset(output.firewall_allowed_domains) == toset(["app.gitpod.io"]) &&
      toset(output.internal_runner_ips) == toset(["10.0.0.10", "10.0.0.11"])
    )
    error_message = "The example outputs must expose the effective public allowlist and restricted runner addresses."
  }
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
