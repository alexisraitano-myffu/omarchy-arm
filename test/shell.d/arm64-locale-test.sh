#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

source "$ROOT/install/arm/locale.sh"

export OMARCHY_ARM_LOCALE_CONF="$test_tmp/locale.conf"
export OMARCHY_ARM_LOCALE_GEN="$test_tmp/locale.gen"

# Run the step against the fixtures, with sudo and locale-gen stubbed out.
sudo() { "$@"; }
locale-gen() { echo generated >"$test_tmp/generated"; }

apply() { rm -f "$test_tmp/generated"; OMARCHY_ARM_DRY_RUN=0 omarchy_arm_apply_locale >/dev/null; }

fixture() {
  printf '%s\n' "$1" >"$OMARCHY_ARM_LOCALE_CONF"
  printf '%s\n' '#en_GB.UTF-8 UTF-8' '#en_US.UTF-8 UTF-8' '#en_US ISO-8859-1' >"$OMARCHY_ARM_LOCALE_GEN"
}

# The stock Arch Linux ARM image: LANG=C and nothing generated.
fixture 'LANG=C'
apply
[[ $(<"$OMARCHY_ARM_LOCALE_CONF") == "LANG=en_US.UTF-8" ]] ||
  fail "LANG=C is replaced with a UTF-8 locale" "$(<"$OMARCHY_ARM_LOCALE_CONF")"
grep -qx 'en_US.UTF-8 UTF-8' "$OMARCHY_ARM_LOCALE_GEN" ||
  fail "the locale is uncommented in locale.gen" "$(<"$OMARCHY_ARM_LOCALE_GEN")"
grep -qx '#en_US ISO-8859-1' "$OMARCHY_ARM_LOCALE_GEN" ||
  fail "only the chosen locale is uncommented" "$(<"$OMARCHY_ARM_LOCALE_GEN")"
[[ -f $test_tmp/generated ]] || fail "locale-gen runs"
pass "LANG=C is replaced with a generated UTF-8 locale"

for lang in '' 'LANG=POSIX' 'LANG="C"'; do
  fixture "$lang"
  apply
  [[ $(<"$OMARCHY_ARM_LOCALE_CONF") == "LANG=en_US.UTF-8" ]] ||
    fail "an unset locale is filled in ($lang)" "$(<"$OMARCHY_ARM_LOCALE_CONF")"
done
pass "an empty, POSIX or quoted C locale is filled in"

# A locale someone chose is theirs.
fixture 'LANG=de_DE.UTF-8'
apply
[[ $(<"$OMARCHY_ARM_LOCALE_CONF") == "LANG=de_DE.UTF-8" ]] || fail "a chosen locale is left alone"
[[ ! -f $test_tmp/generated ]] || fail "nothing is generated when a locale is already set"
pass "a chosen locale is left alone"

# A locale.gen without the entry gets it appended.
fixture 'LANG=C'
: >"$OMARCHY_ARM_LOCALE_GEN"
OMARCHY_ARM_LOCALE=nl_NL.UTF-8 apply
grep -qx 'nl_NL.UTF-8 UTF-8' "$OMARCHY_ARM_LOCALE_GEN" || fail "a missing locale.gen entry is added"
[[ $(<"$OMARCHY_ARM_LOCALE_CONF") == "LANG=nl_NL.UTF-8" ]] || fail "OMARCHY_ARM_LOCALE picks the locale"
pass "OMARCHY_ARM_LOCALE picks the locale, and a missing entry is added"

# Dry run changes nothing.
fixture 'LANG=C'
OMARCHY_ARM_DRY_RUN=1 omarchy_arm_apply_locale >/dev/null
[[ $(<"$OMARCHY_ARM_LOCALE_CONF") == "LANG=C" ]] || fail "dry run leaves locale.conf alone"
pass "dry run changes nothing"

grep -q 'install/arm/locale.sh' "$ROOT/install.sh" && grep -q 'omarchy_arm_apply_locale' "$ROOT/install.sh" ||
  fail "install.sh runs the locale step"
pass "install.sh runs the locale step"
