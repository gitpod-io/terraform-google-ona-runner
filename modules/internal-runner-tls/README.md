# Internal runner TLS identity

This module creates a shared self-signed certificate for the runner's private
DNS name. Private keys remain in Secret Manager; ephemeral reads and write-only
fields keep them out of Terraform state and saved plans. It requires Terraform
1.11+, Google provider 7.6+, and TLS provider 4.4+.

The caller supplies `project_id`, `region`, `secret_prefix`, and `hostname`.
Optional inputs are `generation` (default 1), `kms_key_name`, and `labels`.
Outputs expose the public `certificate_pem` and the pair secret's `secret_id`,
`secret_name`, and numeric `secret_version`. There is no private-key output.

The caller grants Secret Manager CMEK access before creating these resources and
owns runner IAM, public trust distribution, and activation. Follow the root
module's [rotation procedure](../../README.md#internal-runner-tls-preparation)
before changing `generation`. Old versions remain enabled across replacements;
deleting a parent secret deletes its versions.

The [lifecycle test](../../tests/test_internal_runner_tls.py) exercises this
module with real providers against a local HTTP server, including failed applies
and the absence of key material from Terraform artifacts.
