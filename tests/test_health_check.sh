#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
health_check=${1:-"$script_dir/../health-check.sh"}

# Load the production statements without starting authentication or polling.
extract_one() {
  awk -v pattern="$1" '
    $0 ~ pattern { line = $0; count++ }
    END {
      if (count != 1) {
        printf "Expected one statement matching %s; found %d\n", pattern, count > "/dev/stderr"
        exit 1
      }
      print line
    }
  ' "$health_check"
}

runner_assignment=$(extract_one '^[[:space:]]*runner_stable=\$\(')
proxy_assignment=$(extract_one '^[[:space:]]*proxy_stable=\$\(')
core_condition=$(extract_one '^[[:space:]]*if \(\( runner_stable ==.*; then$')

# Variables in this code expand in the child shell, not while building it.
# shellcheck disable=SC2016
printf -v test_code '%s\n' \
  'runner_igm_json=$1' \
  'proxy_igm_json=$2' \
  'ok_runner_size=$3' \
  'ok_runner_health=$4' \
  "$runner_assignment" \
  "$proxy_assignment" \
  'printf "runner=%q proxy=%q " "$runner_stable" "$proxy_stable"' \
  "$core_condition" \
  '  echo healthy' \
  'else' \
  '  echo waiting' \
  'fi'

failures=0
cases=0
run_case() {
  local name=$1 runner_json=$2 proxy_json=$3
  local expected="runner=$4 proxy=$5 $6"
  local actual status=0
  cases=$((cases + 1))
  actual=$(bash -euo pipefail -c "$test_code" bash \
    "$runner_json" "$proxy_json" "${7:-1}" "${8:-1}" 2>&1) || status=$?
  if [[ "$status" == 0 && "$actual" == "$expected" ]]; then
    printf 'PASS %s: %s\n' "$name" "$actual"
  else
    printf 'FAIL %s (exit %s)\n  expected: %s\n  actual:   %s\n' \
      "$name" "$status" "$expected" "$actual" >&2
    failures=$((failures + 1))
  fi
}

stable='{"status": {"isStable": true}}'
unstable='{"status": {"isStable": false}}'

run_case 'both stable' "$stable" "$stable" 1 1 healthy
run_case 'runner unstable' "$unstable" "$stable" 0 1 waiting
run_case 'proxy unstable' "$stable" "$unstable" 1 0 waiting
run_case 'both unstable' "$unstable" "$unstable" 0 0 waiting
run_case 'runner stability absent' '{}' "$stable" 0 1 waiting
run_case 'proxy stability absent' "$stable" '{}' 1 0 waiting
run_case 'runner response empty' '' "$stable" 0 1 waiting
run_case 'proxy response empty' "$stable" '' 1 0 waiting
run_case 'insufficient running instances' "$stable" "$stable" 1 1 waiting 0 1
run_case 'insufficient healthy instances' "$stable" "$stable" 1 1 waiting 1 0

printf '%s cases, %s failures\n' "$cases" "$failures"
[[ "$failures" == 0 ]]
