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


if __name__ == "__main__":
    unittest.main()
