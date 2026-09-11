module "runner" {
  source = "../../modules/restricted-runner"

  project_id         = var.project_id
  runner_id          = var.runner_id
  runner_token       = var.runner_token
  runner_name        = var.runner_name
  region             = var.region
  zones              = var.zones
  vpc_name           = google_compute_network.runner.name
  runner_subnet_name = google_compute_subnetwork.runner.name
  api_endpoint       = var.api_endpoint
  labels             = var.labels

  depends_on = [
    google_compute_network_firewall_policy_association.egress,
    google_compute_global_forwarding_rule.google_apis,
    google_dns_record_set.google_apis,
    google_dns_record_set.google_apis_wildcard,
    google_dns_policy.query_logging,
    google_logging_project_sink.security_archive,
    google_logging_project_sink.security_export,
    google_project_iam_audit_config.extended,
    google_project_iam_member.security_archive_writer,
    google_project_service.required,
  ]
}
