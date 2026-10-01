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
      OMARCHY_ENVIRONMENT_FILE="$environment" OMARCHY_SYS_CPUFREQ="$test_tmp/no-cpufreq" \
      source "$ROOT/install/hardware/arm/cix-sky1.sh"
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

run_boost() {
  local driver="$1"
  rm -rf "$test_tmp/cpufreq" "$test_tmp/tmpfiles"
  mkdir -p "$test_tmp/cpufreq/policy0" "$test_tmp/tmpfiles"
  echo 0 >"$test_tmp/cpufreq/boost"
  echo "$driver" >"$test_tmp/cpufreq/policy0/scaling_driver"
  (
    OMARCHY_PLATFORM_DEVICES="$sky1" OMARCHY_SYS_MODULE="$test_tmp/modules-panthor" \
      OMARCHY_ENVIRONMENT_FILE="$env_file" OMARCHY_SYS_CPUFREQ="$test_tmp/cpufreq" \
      OMARCHY_TMPFILES_DIR="$test_tmp/tmpfiles" source "$ROOT/install/hardware/arm/cix-sky1.sh"
  ) >/dev/null
}

run_boost scmi
[[ $(cat "$test_tmp/cpufreq/boost") == 1 ]] || fail "scmi-cpufreq gets its boost operating points"
grep -qx 'w /sys/devices/system/cpu/cpufreq/boost - - - - 1' "$test_tmp/tmpfiles/cix-sky1-cpufreq-boost.conf" ||
  fail "boost stays on after a reboot"
pass "scmi-cpufreq gets its boost operating points, across reboots"

run_boost cppc_cpufreq
[[ $(cat "$test_tmp/cpufreq/boost") == 0 && ! -e $test_tmp/tmpfiles/cix-sky1-cpufreq-boost.conf ]] ||
  fail "the vendor kernel's CPPC driver is left alone"
pass "the vendor kernel's CPPC driver is left alone"
