#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

source "$ROOT/install/arm/login.sh"

state_dir="$test_tmp/sddm"

seed() {
  OMARCHY_ARM_SDDM_STATE_DIR="$state_dir" OMARCHY_ARM_DRY_RUN=1 omarchy_arm_seed_sddm_state "$@"
}

# The bug this file exists for: the greeter has no username field, and on a
# machine the ISO never touched SDDM has no last user to fall back on. Every
# password is then rejected for user "".
rm -rf "$state_dir"
out=$(seed alice)
[[ $out == *"write $state_dir/state.conf: [Last] Session=omarchy.desktop User=alice"* ]] ||
  fail "a missing state file is seeded with the installing user" "$out"
pass "a missing state file is seeded with the installing user"

# SDDM rewrites state.conf at every login. Once it holds a user that is the
# user's own choice (they may have logged in as someone else), not ours to
# overwrite.
mkdir -p "$state_dir"
printf '[Last]\nSession=omarchy.desktop\nUser=bob\n' >"$state_dir/state.conf"
out=$(seed alice)
[[ $out == *"already remembers a user"* ]] || fail "an existing last user is left alone" "$out"
[[ $(grep '^User=' "$state_dir/state.conf") == "User=bob" ]] ||
  fail "the existing state file is not rewritten"
pass "an existing last user is left alone"

# A state file with an empty User= is the failure mode itself, not a choice.
printf '[Last]\nSession=omarchy.desktop\nUser=\n' >"$state_dir/state.conf"
out=$(seed alice)
[[ $out == *"User=alice"* ]] || fail "an empty last user is treated as missing" "$out"
pass "an empty last user is treated as missing"

# The leaf must be wired after the system is set up and before the user is
# told to enable the display manager, or the first greeter still fails.
grep -q 'install/arm/login.sh' "$ROOT/install.sh" ||
  fail "install.sh sources the login leaf"
grep -q 'omarchy_arm_seed_sddm_state "\$USER"' "$ROOT/install.sh" ||
  fail "install.sh seeds the state for the installing user"
pass "install.sh seeds SDDM's last user"
