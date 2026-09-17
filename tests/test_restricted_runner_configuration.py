#!/usr/bin/env python3

import pathlib
import re
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[1]

PASSTHROUGH_VARIABLES = (
    "development_version",
    "ssh_port",
    "service_ports",
    "proxy_config",
    "ca_certificate",
    "auth_proxy_cert_rotation_triggers",
    "create_cmek",
    "kms_key_name",
    "pre_created_service_accounts",
    "custom_images",
    "enable_agents",
    "enable_cross_zone_restart",
    "use_authoritative_project_metadata",
    "internal_runner_endpoint_version",
)

OPINIONATED_OR_INCOMPATIBLE_VARIABLES = (
    "runner_domain",
    "runner_vm_config",
    "proxy_vm_config",
    "redis_config",
    "certificate_id",
    "certificate_secret_id",
    "certificate_secret_read",
    "loadbalancer_type",
    "routable_subnet_name",
)


class RestrictedRunnerConfigurationTest(unittest.TestCase):
    def assert_declares_variables(self, path: pathlib.Path) -> None:
        source = path.read_text()
        for variable in PASSTHROUGH_VARIABLES:
            with self.subTest(path=path, variable=variable):
                self.assertRegex(source, rf'(?m)^variable "{variable}" \{{')

    def assert_forwards_variables(self, path: pathlib.Path) -> None:
        source = path.read_text()
        for variable in PASSTHROUGH_VARIABLES:
            with self.subTest(path=path, variable=variable):
                self.assertRegex(
                    source,
                    rf"(?m)^\s*{variable}\s*=\s*var\.{variable}\s*$",
                )

    def test_restricted_module_declares_and_forwards_supported_configuration(self) -> None:
        variables_path = REPOSITORY_ROOT / "modules/restricted-runner/variables.tf"
        main_path = REPOSITORY_ROOT / "modules/restricted-runner/main.tf"

        self.assert_declares_variables(variables_path)
        self.assert_forwards_variables(main_path)
        self.assertRegex(
            main_path.read_text(),
            r"(?m)^\s*restrict_ingress\s*=\s*true\s*$",
        )

    def test_networking_example_declares_and_forwards_supported_configuration(self) -> None:
        variables_path = (
            REPOSITORY_ROOT
            / "examples/restricted-runner-with-networking/variables.tf"
        )
        main_path = (
            REPOSITORY_ROOT / "examples/restricted-runner-with-networking/main.tf"
        )

        self.assert_declares_variables(variables_path)
        self.assert_forwards_variables(main_path)

    def test_restricted_module_keeps_topology_configuration_private(self) -> None:
        variables_source = (
            REPOSITORY_ROOT / "modules/restricted-runner/variables.tf"
        ).read_text()
        example_variables_source = (
            REPOSITORY_ROOT
            / "examples/restricted-runner-with-networking/variables.tf"
        ).read_text()

        for variable in OPINIONATED_OR_INCOMPATIBLE_VARIABLES:
            with self.subTest(variable=variable):
                declaration = rf'(?m)^variable "{variable}" \{{'
                self.assertNotRegex(variables_source, declaration)
                self.assertNotRegex(example_variables_source, declaration)

    def test_restricted_runner_omits_proxy_domain_configuration(self) -> None:
        runner_source = (REPOSITORY_ROOT / "runner-vm.tf").read_text()
        cloud_init_source = (
            REPOSITORY_ROOT / "files/runner-cloud-init.tftpl"
        ).read_text()

        self.assertRegex(
            runner_source,
            r'runner_proxy_domain\s*=\s*var\.restrict_ingress\s*\?\s*""\s*:',
        )
        self.assertRegex(
            runner_source,
            r"runner_no_proxy_host\s*=\s*var\.restrict_ingress\s*\?\s*local\.internal_runner_hostname\s*:\s*local\.runner_proxy_domain",
        )
        self.assertRegex(
            cloud_init_source,
            r'%\{ if PROXY_DOMAIN != "" ~\}\s*RUNNER_PROXY_DOMAIN=\$\{PROXY_DOMAIN\}\s*%\{ endif ~\}',
        )
        self.assertRegex(
            cloud_init_source,
            r'%\{ if PROXY_DOMAIN != "" ~\}\s*--runner-proxy-domain=\$\{PROXY_DOMAIN\} \\\s*%\{ endif ~\}',
        )

    def test_networking_uses_valid_google_resource_configuration(self) -> None:
        example_root = (
            REPOSITORY_ROOT / "examples/restricted-runner-with-networking"
        )
        services_source = (example_root / "services.tf").read_text()
        locals_source = (example_root / "locals.tf").read_text()
        inspection_source = (example_root / "inspection.tf").read_text()
        observability_source = (example_root / "observability.tf").read_text()
        main_source = (example_root / "main.tf").read_text()

        self.assertIn('"privateca.googleapis.com"', services_source)
        self.assertIn(
            "url_filtering_profile = "
            "google_network_security_security_profile.url_filtering.id",
            inspection_source,
        )
        self.assertIn("firewall_endpoint = each.value.id", inspection_source)
        self.assertIn(
            "network           = google_compute_network.runner.id",
            inspection_source,
        )
        self.assertNotIn(
            "google_network_security_security_profile.url_filtering.self_link",
            inspection_source,
        )
        self.assertNotIn("firewall_endpoint = each.value.self_link", inspection_source)
        self.assertNotIn("google_compute_network.runner.self_link", inspection_source)
        self.assertIn('replace(local.name_prefix, "/[^a-z0-9]/", "")', locals_source)
        self.assertIn('create = "90m"', inspection_source)
        self.assertNotIn('period = "60s"', observability_source)
        self.assertNotIn(
            'resource "google_project_iam_member" "security_archive_writer"',
            observability_source,
        )
        self.assertNotIn("google_project_iam_member.security_archive_writer", main_source)
        self.assertRegex(
            main_source,
            r"(?s)depends_on\s*=\s*\[.*google_compute_subnetwork\.runner,.*\]",
        )


if __name__ == "__main__":
    unittest.main()
