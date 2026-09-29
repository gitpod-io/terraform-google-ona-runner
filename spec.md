# Health-check stability regression and patched module release

Status: Implemented and verified locally. The user selected main as the
implementation and eventual release base, selected version 4.0.0, and authorized
committing, pushing, and opening a draft PR. Release publication is deferred
until the change is merged and release checks are satisfied.

## Problem and evidence

The workspace remote is `gitpod-io/terraform-google-ona-runner`, matching the
[customer's referenced script](https://github.com/gitpod-io/terraform-google-ona-runner/blob/d549c69b96802411cc7248d2b1ae65f81ab9d48f/health-check.sh#L174).
Both `proxy_stable` and `runner_stable` use `grep -c ... || echo "0"`.
When no line matches, `grep -c` prints `0` and returns status 1. The fallback
prints another zero, so command substitution yields the string `0\n0`.
That string is invalid in the subsequent Bash arithmetic condition.

`health-validation.tf` executes this script through Terraform `local-exec` for
external, internal, and restricted configurations. Restricted configurations
disable the proxy and use `proxy_stable=1`. The defect concerns MIG stability
parsing during provisioning or updates; no evidence ties it specifically to
Docker image selection.

The repository has Terraform and Python tests and a GitHub Actions validation
workflow, but no Bash test framework, Makefile, or Bazel integration. Existing
pre-commit checks include ShellCheck. `VERSION` currently contains `3.2.3`;
the latest published release is `3.2.2` (2026-08-14). GitHub's live public API
confirmed this on 2026-09-29 and confirmed that remote main matches checkout
`0a9456cd42cefbd844823e6d395576fa38c31c25`. Recheck release state at implementation time.

## Requirements

1. Reproduce the defect with an executable, standalone Bash regression test
   before changing production code, and record its expected failing result.
2. Fix both stability assignments. For supported MIG response fixtures,
   stability must be exactly `0` when false or absent and exactly `1` when true.
   Neither value may contain an embedded newline or trigger an arithmetic error.
3. Preserve `set -euo pipefail`, current matching semantics, proxy-disabled
   behavior, retry/timeout behavior, and the existing health acceptance rules.
   An unstable MIG must not pass the core health condition.
4. Run the identical regression test after the fix and record a passing result.
5. Make the test easy to run manually and include it in existing PR/main CI.
6. Publish a module release containing the verified fix through the existing
   release mechanism from main after implementation is authorized. Verify the
   published script, not just the PR. Include accumulated changes and upgrade
   requirements in the release description.

## Constraints and scope

- The planning phase changed only root `spec.md`. Implementation and draft PR
  publication are now authorized; release publication remains a later step.
- The patch should remain small: `health-check.sh`, one Bash test under `tests/`,
  one CI step, and a short contributor-doc command. Version metadata changes
  depend on the selected release path.
- No Bats, shunit2, Make, Bazel, new runtime dependency, JSON-parser migration,
  container image update, cloud deployment, or unrelated script cleanup.
- Tests require Bash and standard local text utilities only. They must not
  require Terraform, GCP credentials, network calls, or real polling delays.
- Leave infrastructure definitions and health-validation trigger versions
  unchanged: this corrects the script used on the next health-check execution;
  it does not promise to rerun a previously successful provisioner immediately.
- Do not retag an existing release or bypass repository merge/release controls.

## Architecture and test design

### Production change

Keep the current `grep -c` pipelines and replace the output-producing fallback
with a successful no-output fallback (`|| true`) in both assignments. This is
an OR fallback, not a pipe to `true`: it runs when the preceding pipeline
returns nonzero. `true` emits no output and returns status 0. When a MIG is
unstable, grep still emits exactly `0`, so the assigned stability value remains
`0`. Only the assignment's command status becomes successful; the MIG is not
marked healthy. Do not simply remove the fallback, which would make the
assignment fail under `set -e` on an expected no-match result during startup.

The overall health decision is separate from the assignment's exit status:
the existing core condition requires `runner_stable == 1`, `proxy_stable == 1`,
and both runner RUNNING and HEALTHY counts to meet `RUNNER_TARGET`.

| Scenario | Expected behavior |
| --- | --- |
| Happy path | Runner and enabled proxy MIGs are stable, and enough runner instances are RUNNING and HEALTHY. The script removes its failure trap and exits 0; Terraform health validation succeeds. |
| Temporarily unstable MIG | Its stability value is `0`, so the core condition is false. The script prints waiting diagnostics, sleeps 10 seconds, and retries. If all core conditions become true before the timeout, it exits 0. |
| Persistently unstable MIG | The core condition remains false. At the timeout check, the script prints the final status and failure guidance, then exits 1, causing Terraform health validation to fail. The script defaults to 600 seconds; the current Terraform callers configure 1,800 seconds. |
| Insufficient RUNNING or HEALTHY runner instances | Even with stable MIGs, the core condition is false. The same retry-then-timeout behavior applies. |
| Required API operation fails | Authentication, MIG-status retrieval, or runner-instance listing failures take the existing immediate failure path and exit nonzero. The grep fallback does not wrap these API calls. |

When the proxy is disabled, its stability value remains the existing sentinel
`1`; runner stability and instance counts still gate success. Proxy backend
health is currently advisory and is not part of the core success condition;
this patch preserves that behavior. Missing stability fields or empty response
bodies count as `0`, never as successful stability evidence.

The regression test must distinguish successful parsing from successful health:
an unstable fixture must produce a successful assignment with the exact value
`0`, while the core health condition must evaluate false without an arithmetic
error. The narrow unit test verifies that decision; retry timing and final
timeout exit behavior are existing script behavior inspected during planning,
not additional end-to-end coverage claimed by this test.

### Smallest Bash unit-test integration

Add `tests/test_health_check.sh`, run with `bash tests/test_health_check.sh`.
Allow an optional script-path argument for verification of a release artifact;
default to the repository's `health-check.sh` relative to the test file.
Exercise the actual two assignment statements from `health-check.sh`, located
by variable name rather than fixed line numbers. Fail clearly if either
expected assignment is absent or ambiguous. Execute them in a fresh Bash
process with `set -euo pipefail` and synthetic runner/proxy JSON variables.
Do not duplicate the parsing expressions in the test or source the entire
script, which would trigger authentication and polling.

For each assignment, test a response with `"isStable": true`, one with
`"isStable": false`, an absent stability field (`{}`), and empty input. Assert
the exact count, successful assignment execution, and no arithmetic diagnostic.
Exercise the production core stability condition with runner/proxy values
`1/1`, `0/1`, `1/0`, and `0/0`, setting the other health flags to 1. Test the
proxy-unstable case with the runner stable so short-circuiting cannot hide it.
Validate the core condition from the production script with a fail-closed
locator as well; exact scalar assertions remain the primary regression check.

Each case should report its name and mismatch on failure, and the test runner
must exit nonzero if any case fails. Resolve repository paths relative to the
test file so invocation is independent of the working directory. No temporary
cloud resources or external mocks are needed. If temporary local files are
used, clean them with an EXIT trap.

This intentionally narrow unit test couples to the assignment/condition layout;
its locator checks must prevent silent coverage loss after refactoring. It
does not validate the complete polling loop, API failures, arbitrary JSON
formatting, or live GCP behavior. A full-script test with fake curl/date/sleep
commands would be a larger follow-up, unnecessary for this defect.

Add a step immediately after checkout in
`.github/workflows/terraform-validate.yml` running the same Bash command, and
document it in `CONTRIBUTING.md`. A manual test alone is feasible, but the
existing workflow makes automatic regression coverage a one-step addition.

## Implementation steps

1. Recheck repository state and release target; preserve unrelated work.
2. Add the Bash regression test against unmodified production code. Run it and
   confirm false/absent cases fail because the captured value is `0\n0`, not
   because of test setup. Ensure both assignments are independently covered.
3. Apply the two fallback changes. Rerun the same test; all cases must pass.
   Run `bash -n health-check.sh`, `bash -n tests/test_health_check.sh`, and applicable
   ShellCheck/pre-commit checks. Separate any pre-existing failures from new ones.
4. Add the CI step and contributor documentation. Verify the documented command,
   test execution from outside the repository directory, YAML/file hygiene, and
   the final diff. Existing Terraform validation CI must remain green.
5. Submit the focused change through the repository PR process and verify checks.
   Include the before/after test results and release intent in the PR.
6. After the change reaches the approved release base, publish the selected
   module version using the existing release workflow and verify its artifacts.

## Release design

The current `.github/workflows/release.yml` runs on pushed tags or manual
dispatch for a supplied tag. It requires the tagged commit to belong to `main`,
creates a GitHub release and module tarball, publishes an existing release
notification, and then increments `VERSION` on `main`. Tests are excluded from
the tarball; the production script is included. There is no dedicated manual
version bump needed if `VERSION` already names the intended unused release.

Before publishing, recheck current tags, releases, `VERSION`, merge status,
and the complete diff from the prior release. A release from today's `main`
would include accumulated changes since `3.2.2`, not solely this health-check
fix. The release workflow also reads the current stable application manifest
for release notes; this patch does not itself change application images.

**Confirmed decision:** implement and release from `main`; no backport. The user
selected major version `4.0.0` to reflect the breaking prerequisite changes,
and `VERSION` has been updated accordingly. Recheck tag availability before
release. Explicitly call out the requirements below in the PR and release notes.

### Other changes already on main

Compared with `3.2.2`, the inspected main has 198 commits: 189 automated image
updates, eight substantive changes, and one next-version bump. The net diff is
49 files, 3,691 insertions, and 163 deletions, before the proposed fix.

| Change | Customer impact | Reference |
| --- | --- | --- |
| Private runner addressing | Opt-in `restrict_ingress` removes proxy/load balancer resources and uses two fixed runner instances with private IPs and DNS; default remains false. | [PR #75](https://github.com/gitpod-io/terraform-google-ona-runner/pull/75) |
| Breaking tool/provider requirements | Terraform minimum rises from 1.3 to 1.11; Google and Google Beta move from 6.x to >=7.6,<8; TLS minimum rises from 4.2 to 4.4. Applies to the root module even when restricted ingress is disabled. | [PR #76](https://github.com/gitpod-io/terraform-google-ona-runner/pull/76) |
| Internal runner HTTPS endpoint | Restricted runners gain Secret Manager-backed TLS, trust-bundle integration, and explicit certificate rotation, with private keys excluded from Terraform state via ephemeral/write-only handling. | [PR #77](https://github.com/gitpod-io/terraform-google-ona-runner/pull/77) |
| Restricted networking example | Adds a dedicated VPC, default-deny egress, Private Service Connect for Google APIs, Cloud NGFW filtering, and observability configuration. | [PR #79](https://github.com/gitpod-io/terraform-google-ona-runner/pull/79) |
| Restricted operational inputs | Wrapper/example support custom CAs, proxies, existing service accounts, CMEK, images, agents, and other operational settings. | [PR #81](https://github.com/gitpod-io/terraform-google-ona-runner/pull/81) |
| Restricted firewall baseline | Updates permitted domains and proxy handling in the restricted networking example. | [PR #82](https://github.com/gitpod-io/terraform-google-ona-runner/pull/82) |
| Security and IAM documentation | Adds GCP security guidance and aligns IAM/deployer permission references. | [PR #71](https://github.com/gitpod-io/terraform-google-ona-runner/pull/71), [PR #78](https://github.com/gitpod-io/terraform-google-ona-runner/pull/78) |
| Default application images | Runner/proxy defaults move from `20260814.483` to `20260928.1073`; Prometheus and node-exporter defaults have no net change. Application behavior is outside this module-diff review. | [Comparison](https://github.com/gitpod-io/terraform-google-ona-runner/compare/3.2.2...0a9456cd42cefbd844823e6d395576fa38c31c25) |

Tests and CI also expand to cover private addressing, restricted input forwarding,
networking, and TLS lifecycle behavior. Customers upgrading from 3.2.2 need to
review the Google provider major-version change and their provider lockfile.
These are pre-existing changes on main, not additions to the health-check patch.

Release success requires the chosen tag to point to a commit containing the
fix, a successful release workflow, a published module tarball whose
`health-check.sh` matches the verified fix, and release notes identifying both
corrected fields. Run the regression test against the script extracted from
the release artifact as a final verification. Record the release URL and exact
module version for the customer. A merged PR alone is not release completion.

## Success criteria

- The same committed test fails on the original implementation for the reported
  duplicate-zero behavior and passes after both assignments are fixed.
- False, absent, and empty responses yield one `0`; true yields one `1`.
- Core stability checks accept both stable MIGs and reject either unstable MIG
  without Bash arithmetic errors or premature failure from no-match status.
- The test is deterministic, runs locally without cloud access, and runs in CI.
- Syntax/lint checks for changed Bash files and required repository CI pass.
- Production changes remain limited to the two stability fallbacks.
- The selected patched module release is published and its script verified.
- The release description discloses accumulated main changes and the breaking
  Terraform/provider requirements; it does not imply a fix-only upgrade.
- Final delivery includes links to the PR and release plus the verified version.

## Local implementation evidence

Before editing production code, the first check executed each original
assignment with a synthetic `isStable: false` response and explicitly asserted
that its value equaled `$'0\n0'`. Both assertions passed; the captured bytes
were `30 0a 30` (zero, newline, zero).

The new regression test was then run before the fix and failed with exit 1:
10 cases, 7 failures. Failures displayed the malformed values and Bash arithmetic
diagnostics. After replacing both fallbacks, the same test passed with exit 0:
10 cases, 0 failures. Copies with only the runner fix or only the proxy fix each
still failed 4 cases, demonstrating that both changes are necessary.

Bash syntax checks, ShellCheck, and all applicable pre-commit checks passed.
Execution from outside the repository and the optional script-path argument
passed. Missing/duplicate assignment fixtures were rejected by the test's
statement locator. The CI step and contributor command are in place. An isolated
Terraform 1.16.4 test using the actual script and mocked API/time commands also
confirmed apply exits 0 for healthy/recovery cases and 1 for persistently
unstable runner/proxy cases and required API failures. Full cloud tests and
release-artifact verification remain outside this local verification.
