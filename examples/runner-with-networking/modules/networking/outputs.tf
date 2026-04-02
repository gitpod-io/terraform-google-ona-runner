# VPC connector not needed - using direct VPC deployment for VM services

output "vpc_name" {
  description = "Name of the VPC"
  value       = google_compute_network.vpc.name
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = google_compute_network.vpc.id
}

output "runner_subnet_name" {
  description = "Name of the runner subnet"
  value       = google_compute_subnetwork.runner_subnet.name
}

output "runner_subnet_id" {
  description = "ID of the runner subnet"
  value       = google_compute_subnetwork.runner_subnet.id
}

output "router_name" {
  description = "Name of the Cloud Router (if created)"
  value       = google_compute_router.router.name
}

output "nat_name" {
  description = "Name of the Cloud NAT (if created)"
  value       = google_compute_router_nat.nat.name
}
