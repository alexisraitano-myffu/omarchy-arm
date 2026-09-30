#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

export PATH="$ROOT/bin:$PATH"
export OMARCHY_INSTALL="$ROOT/install"
export OMARCHY_ARCH=aarch64
export OMARCHY_DEVICETREE="$test_tmp/no-devicetree"

sky1="$test_tmp/acpi-sky1"
mkdir -p "$sky1/CIXH5010:00" "$sky1/CIXH5000:00" "$test_tmp/acpi-none"
mkdir -p "$test_tmp/modules-vendor/mali_kbase" "$test_tmp/modules-panthor/panthor"

run_leaf() {
  local devices="$1" modules="$2" environment="$3"
  (
    OMARCHY_PLATFORM_DEVICES="$devices" OMARCHY_SYS_MODULE="$modules" \
      OMARCHY_ENVIRONMENT_FILE="$environment" source "$ROOT/install/hardware/arm/cix-sky1.sh"
  ) >/dev/null
}

env_file="$test_tmp/environment"
printf '# pam_env\n' >"$env_file"
run_leaf "$sky1" "$test_tmp/modules-vendor" "$env_file"
grep -qx 'LIBGL_ALWAYS_SOFTWARE=1' "$env_file" ||
  fail "an MS-R1 on the vendor kernel renders in software" "$(cat "$env_file")"
pass "an MS-R1 on the vendor kernel renders in software"

run_leaf "$sky1" "$test_tmp/modules-vendor" "$env_file"
[[ $(grep -c '^LIBGL_ALWAYS_SOFTWARE=' "$env_file") == 1 ]] || fail "running the leaf twice adds nothing"
pass "running the leaf twice adds nothing"

printf '# pam_env\n' >"$env_file"
run_leaf "$sky1" "$test_tmp/modules-panthor" "$env_file"
grep -q '^LIBGL_ALWAYS_SOFTWARE=' "$env_file" && fail "a kernel with panthor keeps Mesa's GPU driver"
pass "a kernel with panthor keeps Mesa's GPU driver"

run_leaf "$test_tmp/acpi-none" "$test_tmp/modules-vendor" "$env_file"
grep -q '^LIBGL_ALWAYS_SOFTWARE=' "$env_file" && fail "the leaf does nothing on another board"
pass "the leaf does nothing on another board"
