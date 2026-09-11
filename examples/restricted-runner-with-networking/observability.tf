resource "google_project_iam_audit_config" "extended" {
  for_each = local.extended_audit_services

  project = var.project_id
  service = each.value

  dynamic "audit_log_config" {
    for_each = toset(["ADMIN_READ", "DATA_READ", "DATA_WRITE"])

    content {
      log_type = audit_log_config.value
    }
  }
}

resource "google_logging_project_bucket_config" "security_archive" {
  project          = var.project_id
  location         = var.security_log_bucket_location
  bucket_id        = "${local.name_prefix}-security"
  description      = "Cloud-generated network and audit evidence for the restricted Ona runner."
  retention_days   = var.security_log_retention_days
  enable_analytics = true
  locked           = var.lock_security_log_bucket
  deletion_policy  = var.lock_security_log_bucket ? "ABANDON" : "DELETE"
}

resource "google_logging_project_sink" "security_archive" {
  project                = var.project_id
  name                   = "${local.name_prefix}-security"
  description            = "Routes restricted-runner network and audit evidence to the dedicated security archive."
  destination            = "logging.googleapis.com/${google_logging_project_bucket_config.security_archive.id}"
  filter                 = local.security_log_filter
  unique_writer_identity = true
}

resource "google_project_iam_member" "security_archive_writer" {
  project = var.project_id
  role    = "roles/logging.bucketWriter"
  member  = google_logging_project_sink.security_archive.writer_identity
}

resource "google_logging_project_sink" "security_export" {
  for_each = var.security_log_export_destinations

  project                = var.project_id
  name                   = trimsuffix(substr("${local.name_prefix}-${each.key}", 0, 100), "-")
  description            = "Exports restricted-runner network and audit evidence to ${each.key}."
  destination            = each.value
  filter                 = local.security_log_filter
  unique_writer_identity = true
}

resource "google_logging_metric" "dns_nxdomain" {
  project     = var.project_id
  name        = "${local.name_prefix}-dns-nxdomain"
  description = "NXDOMAIN responses observed from the restricted runner VPC."
  filter = join("\n", [
    "resource.type=\"dns_query\"",
    "log_id(\"dns.googleapis.com/dns_queries\")",
    "jsonPayload.responseCode=3",
  ])
}

resource "google_monitoring_alert_policy" "denied_egress" {
  project               = var.project_id
  display_name          = "${local.name_prefix}: denied egress"
  combiner              = "OR"
  enabled               = true
  severity              = "WARNING"
  notification_channels = var.security_notification_channels
  user_labels           = { ona_component = "runner_networking" }

  conditions {
    display_name = "Cloud NGFW denied an egress connection"

    condition_matched_log {
      filter = join("\n", [
        "resource.type=\"gce_subnetwork\"",
        "log_id(\"compute.googleapis.com/firewall\")",
        "jsonPayload.disposition=\"DENIED\"",
        "jsonPayload.vpc.vpc_name=\"${google_compute_network.runner.name}\"",
      ])
      label_extractors = {
        destination_ip = "EXTRACT(jsonPayload.connection.dest_ip)"
        vm_name        = "EXTRACT(jsonPayload.instance.vm_name)"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"

    notification_rate_limit {
      period = "300s"
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = "Investigate the VM named in the alert. Environment VM names contain the Ona environment ID."
  }
}

resource "google_monitoring_alert_policy" "environment_api_denied" {
  project               = var.project_id
  display_name          = "${local.name_prefix}: environment API denied"
  combiner              = "OR"
  enabled               = true
  severity              = "WARNING"
  notification_channels = var.security_notification_channels
  user_labels           = { ona_component = "runner_networking" }

  conditions {
    display_name = "The environment VM service account was denied by a Google API"

    condition_matched_log {
      filter = join("\n", [
        "log_id(\"cloudaudit.googleapis.com/policy\")",
        "protoPayload.authenticationInfo.principalEmail=\"${module.runner.environment_vm_service_account_email}\"",
      ])
      label_extractors = {
        method  = "EXTRACT(protoPayload.methodName)"
        service = "EXTRACT(protoPayload.serviceName)"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"

    notification_rate_limit {
      period = "300s"
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = "Review the denied API operation and correlate its timestamp and caller IP with DNS, NAT, firewall, and VPC flow records. Concurrent environments share this service-account identity, so exact origin attribution can be ambiguous."
  }
}

resource "google_monitoring_alert_policy" "security_control_change" {
  project               = var.project_id
  display_name          = "${local.name_prefix}: security control changed"
  combiner              = "OR"
  enabled               = true
  severity              = "ERROR"
  notification_channels = var.security_notification_channels
  user_labels           = { ona_component = "runner_networking" }

  conditions {
    display_name = "A restricted-runner security control was modified"

    condition_matched_log {
      filter = trimspace(<<-EOT
        log_id("cloudaudit.googleapis.com/activity")
        AND
        (
          (
            protoPayload.resourceName:"${local.name_prefix}"
            AND
            protoPayload.methodName=~"(?i)(delete|disable|patch|remove|setIamPolicy|update)"
          ) OR
          protoPayload.methodName:"SetIamPolicy"
        )
      EOT
      )
      label_extractors = {
        method   = "EXTRACT(protoPayload.methodName)"
        resource = "EXTRACT(protoPayload.resourceName)"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"

    notification_rate_limit {
      period = "300s"
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = "Confirm that the change was expected. In particular, verify the firewall policy, DNS policy, log sinks, archive, packet mirroring, and IAM audit configuration."
  }
}

resource "google_monitoring_alert_policy" "dns_nxdomain" {
  project               = var.project_id
  display_name          = "${local.name_prefix}: DNS NXDOMAIN anomaly"
  combiner              = "OR"
  enabled               = true
  severity              = "WARNING"
  notification_channels = var.security_notification_channels
  user_labels           = { ona_component = "runner_networking" }

  conditions {
    display_name = "NXDOMAIN responses exceeded the five-minute threshold"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.dns_nxdomain.name}\" AND resource.type=\"dns_query\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.dns_nxdomain_alert_threshold
      duration        = "0s"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = "Review query names and source VM IDs for domain-generation behavior, DNS tunneling, or broken allowlist assumptions."
  }
}

resource "google_monitoring_alert_policy" "inspection_fallback" {
  project               = var.project_id
  display_name          = "${local.name_prefix}: inspection fallback allowed traffic"
  combiner              = "OR"
  enabled               = true
  severity              = "CRITICAL"
  notification_channels = var.security_notification_channels
  user_labels           = { ona_component = "runner_networking" }

  conditions {
    display_name = "Cloud NGFW used the ALLOW fallback action"

    condition_matched_log {
      filter = join("\n", [
        "log_id(\"compute.googleapis.com/firewall\")",
        "jsonPayload.rule_details.apply_security_profile_fallback_action=\"ALLOW\"",
        "jsonPayload.vpc.vpc_name=\"${google_compute_network.runner.name}\"",
      ])
      label_extractors = {
        vm_name = "EXTRACT(jsonPayload.instance.vm_name)"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"

    notification_rate_limit {
      period = "60s"
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = "Treat this as a fail-open event. Verify that every configured zone has an active firewall endpoint association before continuing workloads."
  }
}
