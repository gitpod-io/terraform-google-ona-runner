# Ona GCP Runner

[![Build with Ona](https://gitpod.io/button/open-in-gitpod.svg)](https://gitpod.io/#https://github.com/gitpod-io/terraform-google-ona-runner)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Quick Start

1. **Clone and configure**:
   ```bash
   git clone <repository-url>
   cd <repository-directory>
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit `terraform.tfvars`** with your values:
   ```hcl
   project_id         = "your-gcp-project-id"
   region             = "us-central1"
   zones              = ["us-central1-a", "us-central1-b", "us-central1-c"]
   runner_name        = "my-ona-runner"
   runner_id          = "your-runner-id"          # From Ona dashboard
   runner_token       = "your-runner-token"       # From Ona dashboard
   runner_domain      = "ona.example.com"
   vpc_name           = "your-existing-vpc"       # Existing VPC name
   runner_subnet_name = "your-existing-subnet"   # Existing subnet name
   certificate_id     = "projects/your-project/locations/global/certificates/your-cert"  # Certificate Manager resource ID

   # Optional: Proxy configuration
   proxy_config = {
     http_proxy  = "http://proxy.example.com:8080"
     https_proxy = "http://proxy.example.com:8080"
     all_proxy   = "http://proxy.example.com:8080"
     no_proxy    = "localhost,127.0.0.1,metadata.google.internal"
   }

   # Optional: Custom CA certificate (choose one method)
   ca_certificate = {
     file_path = "/path/to/ca-certificate.pem"  # OR
     content   = "-----BEGIN CERTIFICATE-----\n..."
   }

   # Optional: Use pre-created service accounts
   pre_created_service_accounts = {
     runner           = "my-runner@my-project.iam.gserviceaccount.com"
     environment_vm   = "my-env-vm@my-project.iam.gserviceaccount.com"
     build_cache      = "my-build-cache@my-project.iam.gserviceaccount.com"
     secret_manager   = "my-secrets@my-project.iam.gserviceaccount.com"
     pubsub_processor = "my-pubsub@my-project.iam.gserviceaccount.com"
     proxy_vm         = "my-proxy-vm@my-project.iam.gserviceaccount.com"
   }
   ```

3. **Deploy**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```
