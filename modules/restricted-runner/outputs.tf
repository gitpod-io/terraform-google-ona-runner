output "internal_runner_ips" {
  description = "Static internal IP addresses assigned to the runner instances."
  value       = module.runner.internal_runner_ips
}

output "internal_runner_hostname" {
  description = "Private DNS hostname shared by the runner instances."
  value       = module.runner.internal_runner_hostname
}

output "runner_instance_group_name" {
  description = "Name of the regional runner managed instance group."
  value       = module.runner.runner_instance_group_name
}

output "runner_service_account_email" {
  description = "Service account used by runner instances."
  value       = module.runner.runner_service_account_email
}

output "environment_vm_service_account_email" {
  description = "Service account used by environment instances."
  value       = module.runner.environment_vm_service_account_email
}

output "logs_url" {
  description = "Cloud Logging query URL for runner logs."
  value       = module.runner.logs_url
}
