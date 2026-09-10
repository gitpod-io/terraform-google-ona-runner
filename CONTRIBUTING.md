# Contributing

[![Build with Ona](https://gitpod.io/button/open-in-gitpod.svg)](https://gitpod.io/#https://github.com/gitpod-io/terraform-google-ona-runner)

This document provides guidelines for contributing to the Ona GCP Runner Terraform module.

## Development Environment

The easiest way to get started is to open this repository in [Ona](https://ona.com/) or run the included [dev container](.devcontainer/) locally with [VS Code Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers) or any compatible IDE. The dev container comes pre-configured with all required tools.

If you prefer a manual setup, install the following:

- [Terraform](https://terraform.io/) >= 1.11
- [Google Cloud SDK](https://cloud.google.com/sdk/install)
- [pre-commit](https://pre-commit.com/)
- [terraform-docs](https://github.com/terraform-docs/terraform-docs)

## File Structure

| Path | Description |
|---|---|
| `*.tf` | Root module resources |
| `variables.tf` | Input variables |
| `outputs.tf` | Output values |
| `versions.tf` | Provider and Terraform version constraints |
| `modules/` | Submodules |
| `examples/` | Example configurations |
| `docs/` | Additional documentation |
| `files/` | Template files used by resources |

## Making Changes

1. Fork the repository and create a feature branch.
2. Make your changes, following the conventions below.
3. Run linting and formatting checks.
4. Submit a pull request against `main`.

### Linting and Formatting

This repository uses [pre-commit](https://pre-commit.com/) hooks for `terraform fmt`, `terraform-docs`, `shellcheck`, and general file hygiene. Install the hooks once after cloning:

```bash
pre-commit install
```

To run all checks manually:

```bash
pre-commit run --all-files
```

### Terraform tests

Run the private runner addressing tests with Terraform 1.16 or later:

```bash
terraform init -backend=false
terraform test -filter=tests/internal-runner.tftest.hcl
```

These tests use real provider schemas with resource and data overrides
and plan operations, so they do not need cloud credentials or create resources.
They cover defaults, private addressing, Shared VPC placement, public trust,
versioned runner configuration, and managed versus externally managed TLS IAM. Module deployments retain the
Terraform version requirement in `versions.tf`.

### Internal TLS lifecycle test

Run `python3 tests/test_internal_runner_tls.py` with Terraform 1.11+, Python 3,
and OpenSSL installed. It loads the production `internal-runner-tls.tf` resources
into an isolated fixture with synthetic DNS and IAM inputs, using Google 7.6.0 and
TLS 4.4.0 providers against a local Secret Manager HTTP test server. Use
`--google-provider-version=<version>` to verify another Google provider version. It generates
only test identities, uses no cloud credentials, and removes its temporary
working directory on completion.

The test checks interrupted saved-plan applies, retry, unchanged plans, explicit
key rotation, replacement secrets whose version numbering restarts, automatic
and CMEK replication, certificate/key matching, and private-key exclusion from
state, backups, and unpacked saved plans. The HTTP server verifies configured
replication payloads; it does not establish live GCP IAM or KMS access.

### Generating Documentation

Input and output tables in README files are generated automatically by `terraform-docs` via pre-commit. If you change `variables.tf` or `outputs.tf`, the tables will be updated on your next commit. You can also regenerate them manually:

```bash
pre-commit run terraform_docs --all-files
```

## License

By contributing, you agree that your contributions will be licensed under the [Mozilla Public License 2.0](LICENSE).
