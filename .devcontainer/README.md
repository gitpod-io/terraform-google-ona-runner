# Terraform & Google Cloud Development Environment

This devcontainer is configured for Terraform and Google Cloud development with Ona compatibility.

## Included Tools
- Terraform (installed via HashiCorp APT repository)
- Google Cloud CLI (installed via Google APT repository)
- HashiCorp Terraform VSCode extension
- Google Cloud Code extension
- Python3 and pip for additional tooling

## Installation Method
Tools are installed directly in the Dockerfile using official APT repositories for maximum compatibility with Gitpod.

## Usage
The environment will automatically install and configure all tools when the container builds.

## Verification
Run `terraform --version && gcloud --version` to verify installation.

## Port Forwarding
- Port 8080: Application
- Port 3000: Development Server
