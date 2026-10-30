#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

export PATH="$ROOT/bin:$PATH"

# Every aarch64 board describes itself in the flattened device tree; the
# properties are NUL-separated, which is the detail a naive `cat | grep` gets
# wrong on a board whose first compatible entry is not the one we match.
fixture() {
  local name="$1" compatible="$2" model="${3:-}"
  local dir="$test_tmp/$name"

  mkdir -p "$dir"
  printf '%s\0' $compatible >"$dir/compatible"
  [[ -n $model ]] && printf '%s\0' "$model" >"$dir/model"
  echo "$dir"
}

# ACPI platform devices: an empty directory unless a test names one, so the
# host running the tests (which may itself be a Sky1) never leaks in.
mkdir -p "$test_tmp/no-acpi"

platform_of() {
  OMARCHY_ARCH="${2:-aarch64}" OMARCHY_DEVICETREE="$1" \
    OMARCHY_PLATFORM_DEVICES="${3:-$test_tmp/no-acpi}" omarchy-hw-platform
}

pi5=$(fixture pi5 "raspberrypi,5-model-b brcm,bcm2712" "Raspberry Pi 5 Model B Rev 1.0")
pi4=$(fixture pi4 "raspberrypi,4-model-b brcm,bcm2711" "Raspberry Pi 4 Model B Rev 1.4")
mac=$(fixture mac "apple,j413 apple,t8112 apple,arm-platform" "Apple MacBook Air (13-inch, M2, 2022)")
vm=$(fixture vm "linux,dummy-virt")
pbp=$(fixture pbp "pine64,pinebook-pro rockchip,rk3399" "Pine64 Pinebook Pro")
# A device tree that only names the machine in its model string.
pbp_model=$(fixture pbp_model "rockchip,rk3399" "Pine64 Pinebook Pro")
# Another RK3399 board must not be taken for a Pinebook Pro.
rockpro=$(fixture rockpro "pine64,rockpro64-v2.1 pine64,rockpro64 rockchip,rk3399" "Pine64 RockPro64 v2.1")
# An Asahi kernel old enough to predate the apple,arm-platform compatible.
mac_old=$(fixture mac_old "apple,j274" "Apple Mac mini (M1, 2020)")

[[ $(platform_of "$pi5") == "raspberry-pi-5" ]] || fail "a Pi 5 is recognised" "$(platform_of "$pi5")"
pass "a Pi 5 is recognised"

[[ $(platform_of "$pi4") == "raspberry-pi" ]] || fail "an older Pi is recognised but not as a Pi 5" "$(platform_of "$pi4")"
pass "an older Pi is recognised but not as a Pi 5"

[[ $(platform_of "$mac") == "apple-silicon" ]] || fail "an Apple Silicon Mac is recognised" "$(platform_of "$mac")"
pass "an Apple Silicon Mac is recognised"

[[ $(platform_of "$mac_old") == "apple-silicon" ]] || fail "a Mac is recognised from its model string alone" "$(platform_of "$mac_old")"
pass "a Mac is recognised from its model string alone"

[[ $(platform_of "$pbp") == "pinebook-pro" ]] || fail "a Pinebook Pro is recognised" "$(platform_of "$pbp")"
pass "a Pinebook Pro is recognised"

[[ $(platform_of "$pbp_model") == "pinebook-pro" ]] ||
  fail "a Pinebook Pro is recognised from its model string alone" "$(platform_of "$pbp_model")"
pass "a Pinebook Pro is recognised from its model string alone"

[[ $(platform_of "$rockpro") == "generic-aarch64" ]] ||
  fail "another RK3399 board is not taken for a Pinebook Pro" "$(platform_of "$rockpro")"
pass "another RK3399 board is not taken for a Pinebook Pro"

[[ $(platform_of "$vm") == "generic-aarch64" ]] || fail "an aarch64 VM falls through to generic" "$(platform_of "$vm")"
pass "an aarch64 VM falls through to generic"

[[ $(platform_of "$test_tmp/nonexistent") == "generic-aarch64" ]] ||
  fail "a machine with no device tree falls through to generic"
pass "a machine with no device tree falls through to generic"

# The CIX Sky1: its device tree when booted with one, and on ACPI-only
# firmware (the Minisforum MS-R1) the CIXH5010 display engines the DSDT names.
sky1_dt=$(fixture sky1_dt "radxa,orion-o6 cix,sky1" "Radxa Orion O6")
[[ $(platform_of "$sky1_dt") == "cix-sky1" ]] || fail "a Sky1 is recognised from its device tree" "$(platform_of "$sky1_dt")"
pass "a Sky1 is recognised from its device tree"

acpi="$test_tmp/acpi-sky1"
mkdir -p "$acpi/CIXH5010:00" "$acpi/CIXH5010:03" "$acpi/CIXH5000:00"
[[ $(platform_of "$test_tmp/nonexistent" aarch64 "$acpi") == "cix-sky1" ]] ||
  fail "an ACPI-only Sky1 (MS-R1) is recognised from its display engines"
pass "an ACPI-only Sky1 (MS-R1) is recognised from its display engines"

acpi_other="$test_tmp/acpi-other"
mkdir -p "$acpi_other/ARMH0011:00" "$acpi_other/ARMHD620:00"
[[ $(platform_of "$test_tmp/nonexistent" aarch64 "$acpi_other") == "generic-aarch64" ]] ||
  fail "another ACPI machine still falls through to generic"
pass "another ACPI machine still falls through to generic"

OMARCHY_ARCH=aarch64 OMARCHY_DEVICETREE="$test_tmp/nonexistent" OMARCHY_PLATFORM_DEVICES="$acpi" omarchy-hw-cix-sky1 ||
  fail "omarchy-hw-cix-sky1 matches an MS-R1"
pass "omarchy-hw-cix-sky1 matches an MS-R1"

OMARCHY_ARCH=aarch64 OMARCHY_DEVICETREE="$pi4" OMARCHY_PLATFORM_DEVICES="$test_tmp/no-acpi" omarchy-hw-cix-sky1 &&
  fail "omarchy-hw-cix-sky1 rejects a Pi"
pass "omarchy-hw-cix-sky1 rejects a Pi"

# The predicates are what the install leaves and the Hyprland profile branch
# on, so an x86 machine must never reach an ARM code path.
[[ $(platform_of "$mac" x86_64) == "x86_64" ]] || fail "an x86_64 machine reports its architecture, not a board"
pass "an x86_64 machine reports its architecture, not a board"

OMARCHY_ARCH=x86_64 omarchy-hw-aarch64 && fail "omarchy-hw-aarch64 is false on x86_64"
pass "omarchy-hw-aarch64 is false on x86_64"

OMARCHY_ARCH=aarch64 omarchy-hw-aarch64 || fail "omarchy-hw-aarch64 is true on aarch64"
pass "omarchy-hw-aarch64 is true on aarch64"

OMARCHY_ARCH=aarch64 OMARCHY_DEVICETREE="$mac" omarchy-hw-apple-silicon ||
  fail "omarchy-hw-apple-silicon matches an M-series Mac"
pass "omarchy-hw-apple-silicon matches an M-series Mac"

# An Intel T2 Mac is x86_64. The T2 quirks under install/hardware/apple/ are
# for that machine, and this predicate must not claim it.
OMARCHY_ARCH=x86_64 OMARCHY_DEVICETREE="$mac" omarchy-hw-apple-silicon &&
  fail "omarchy-hw-apple-silicon does not match an Intel T2 Mac"
pass "omarchy-hw-apple-silicon does not match an Intel T2 Mac"

OMARCHY_ARCH=aarch64 OMARCHY_DEVICETREE="$pbp" omarchy-hw-pinebook-pro ||
  fail "omarchy-hw-pinebook-pro matches a Pinebook Pro"
OMARCHY_ARCH=aarch64 OMARCHY_DEVICETREE="$rockpro" omarchy-hw-pinebook-pro &&
  fail "omarchy-hw-pinebook-pro rejects another RK3399 board"
pass "omarchy-hw-pinebook-pro matches only a Pinebook Pro"

OMARCHY_ARCH=aarch64 OMARCHY_DEVICETREE="$pi4" omarchy-hw-raspberry-pi --5 &&
  fail "omarchy-hw-raspberry-pi --5 rejects an older Pi"
pass "omarchy-hw-raspberry-pi --5 rejects an older Pi"

OMARCHY_ARCH=aarch64 OMARCHY_DEVICETREE="$pi4" omarchy-hw-raspberry-pi ||
  fail "omarchy-hw-raspberry-pi accepts an older Pi"
pass "omarchy-hw-raspberry-pi accepts an older Pi"
