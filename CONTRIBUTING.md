# Contributing

This document provides guidelines for contributing to the Ona GCP Runner Terraform module.

## Development Environment

The easiest way to get started is with the included [dev container](.devcontainer/), which comes pre-configured with all required tools. If you prefer a local setup, install the following:

- [Terraform](https://terraform.io/) >= 1.0
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

### Generating Documentation

Input and output tables in README files are generated automatically by `terraform-docs` via pre-commit. If you change `variables.tf` or `outputs.tf`, the tables will be updated on your next commit. You can also regenerate them manually:

```bash
pre-commit run terraform_docs --all-files
```

## License

By contributing, you agree that your contributions will be licensed under the [Mozilla Public License 2.0](LICENSE).
