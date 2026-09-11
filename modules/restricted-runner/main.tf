module "runner" {
  source = "../.."

  project_id         = var.project_id
  runner_id          = var.runner_id
  runner_token       = var.runner_token
  runner_name        = var.runner_name
  region             = var.region
  zones              = var.zones
  vpc_name           = var.vpc_name
  vpc_project_id     = var.vpc_project_id
  runner_subnet_name = var.runner_subnet_name
  api_endpoint       = var.api_endpoint
  labels             = var.labels
  restrict_ingress   = true
}
