terraform {
  required_version = ">= 1.11"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.6, < 8.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.4, < 5.0"
    }
  }
}
