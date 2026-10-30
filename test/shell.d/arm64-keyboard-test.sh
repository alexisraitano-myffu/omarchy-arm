#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

source "$ROOT/install/arm/keyboard.sh"

# A stand-in for xkeyboard-config's rules list, so the tests assert against a
# known catalogue rather than whatever the machine running them has installed.
# Shaped like the real file: named sections, each ended by the next "!".
cat >"$test_tmp/base.lst" <<'LST'
! model
  pc105           Generic 105-key PC

! layout
  us              English (US)
  gb              English (UK)
  fr              French
  de              German
  es              Spanish
  br              Portuguese (Brazil)
  ch              German (Switzerland)
  be              Belgian
  latam           Spanish (Latin American)

! variant
  dvorak          us: English (Dvorak)
LST

detect() {
  OMARCHY_ARM_VCONSOLE="$test_tmp/vconsole.conf" \
  OMARCHY_ARM_X11_KEYMAP="$test_tmp/00-keyboard.conf" \
  OMARCHY_ARM_XKB_RULES="$test_tmp/base.lst" \
    omarchy_arm_detect_keyboard
}

fixture() {
  rm -f "$test_tmp/vconsole.conf" "$test_tmp/00-keyboard.conf"
  [[ -n ${1:-} ]] && printf '%s\n' "$1" >"$test_tmp/vconsole.conf"
  [[ -n ${2:-} ]] && printf '%s\n' "$2" >"$test_tmp/00-keyboard.conf"
  return 0
}

# The whole point: default/hypr/input.lua reads XKBLAYOUT and falls back to us.
# A machine that already declares a layout must not end up in US.
fixture 'XKBLAYOUT=fr'
[[ $(detect | cut -d'|' -f1) == "fr" ]] || fail "XKBLAYOUT is used when it is already set" "$(detect)"
[[ $(detect | cut -d'|' -f3) == "$test_tmp/vconsole.conf" ]] ||
  fail "an already-correct vconsole.conf is reported as needing nothing"
pass "XKBLAYOUT is used when it is already set"

fixture 'XKBLAYOUT="be"
XKBVARIANT="oss"'
[[ $(detect | cut -d'|' -f1,2) == 'be|oss' ]] || fail "the variant comes along, quotes stripped" "$(detect)"
pass "the variant comes along, and quoting is stripped"

# localectl set-x11-keymap writes this, and it is the authoritative xkb answer.
fixture '' 'Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "de"
        Option "XkbVariant" "nodeadkeys"
EndSection'
[[ $(detect | cut -d'|' -f1,2) == 'de|nodeadkeys' ]] || fail "the X11 keymap is read when vconsole has no XKBLAYOUT" "$(detect)"
pass "the X11 keymap is read when vconsole has no XKBLAYOUT"

# XKBLAYOUT wins: it is what Omarchy actually reads, so anything else would be
# reporting a layout the desktop will not use.
fixture 'XKBLAYOUT=fr' 'Section "InputClass"
        Option "XkbLayout" "de"
EndSection'
[[ $(detect | cut -d'|' -f1) == "fr" ]] || fail "XKBLAYOUT wins over the X11 config" "$(detect)"
pass "XKBLAYOUT wins over the X11 config"

# A command-line Arch install very often sets KEYMAP and nothing else. Console
# keymap names are not xkb layout names.
for case in "fr-latin9 fr" "de-latin1-nodeadkeys de" "fr fr" "es es" "br-abnt2 br"; do
  set -- $case
  fixture "KEYMAP=$1"
  [[ $(detect | cut -d'|' -f1) == "$2" ]] || fail "the console keymap $1 maps to $2" "$(detect)"
done
pass "console keymaps are reduced to their xkb layout"

# The ones where the base name itself differs.
fixture 'KEYMAP=uk'
[[ $(detect | cut -d'|' -f1) == "gb" ]] || fail "uk maps to gb, not uk" "$(detect)"
fixture 'KEYMAP=dvorak'
[[ $(detect | cut -d'|' -f1,2) == 'us|dvorak' ]] || fail "dvorak maps to us with a variant" "$(detect)"
fixture 'KEYMAP=sg'
[[ $(detect | cut -d'|' -f1,2) == 'ch|de' ]] || fail "sg maps to ch/de" "$(detect)"
pass "aliased keymaps map to their real xkb layout and variant"

# Guessing at a keymap nobody recognises would be worse than the default: a
# layout Hyprland rejects leaves a desktop with no working keyboard at all.
fixture 'KEYMAP=some-unknown-thing-42'
[[ -z $(detect) ]] || fail "an unrecognised keymap is left alone" "$(detect)"
fixture ''
[[ -z $(detect) ]] || fail "a machine that declares nothing detects nothing" "$(detect)"
pass "an unrecognised or absent keymap falls through to the shipped default"

# A dry run must not write to the file it is reporting on.
fixture 'KEYMAP=fr-latin9'
before=$(cat "$test_tmp/vconsole.conf")
out=$(OMARCHY_ARM_DRY_RUN=1 OMARCHY_ARM_VCONSOLE="$test_tmp/vconsole.conf" \
      OMARCHY_ARM_X11_KEYMAP="$test_tmp/00-keyboard.conf" \
      OMARCHY_ARM_XKB_RULES="$test_tmp/base.lst" omarchy_arm_apply_keyboard)
[[ $(cat "$test_tmp/vconsole.conf") == "$before" ]] || fail "a dry run changes nothing" "$(cat "$test_tmp/vconsole.conf")"
grep -q "XKBLAYOUT=fr" <<<"$out" || fail "a dry run says what it would write" "$out"
pass "a dry run reports without writing"

# An empty variant used to shift every later field left, putting the source
# string where the variant belonged and announcing a layout nobody asked for.
fixture 'KEYMAP=fr'
out=$(OMARCHY_ARM_DRY_RUN=1 OMARCHY_ARM_VCONSOLE="$test_tmp/vconsole.conf" \
      OMARCHY_ARM_X11_KEYMAP="$test_tmp/00-keyboard.conf" \
      OMARCHY_ARM_XKB_RULES="$test_tmp/base.lst" omarchy_arm_apply_keyboard)
grep -q "^Keyboard layout: fr, from KEYMAP=fr in " <<<"$out" ||
  fail "an empty variant does not shift the fields along" "$out"
grep -q "XKBVARIANT" <<<"$out" && fail "no empty variant is written" "$out"
pass "an empty variant does not shift the reported fields along"

fixture 'KEYMAP=sg'
out=$(OMARCHY_ARM_DRY_RUN=1 OMARCHY_ARM_VCONSOLE="$test_tmp/vconsole.conf" \
      OMARCHY_ARM_X11_KEYMAP="$test_tmp/00-keyboard.conf" \
      OMARCHY_ARM_XKB_RULES="$test_tmp/base.lst" omarchy_arm_apply_keyboard)
grep -q "^Keyboard layout: ch (de), from KEYMAP=sg in " <<<"$out" ||
  fail "a real variant is reported in its own place" "$out"
grep -q "XKBVARIANT=de" <<<"$out" || fail "a real variant is written" "$out"
pass "a real variant is reported and written in its own place"

# A name that only looks like a layout is worse than no name at all:
# libxkbcommon will not compile a keymap for it, Hyprland comes up with no
# keyboard, and the lock screen then rejects a password that was typed right.
# "en" is the one people write, and it passed the old two-or-three-letters
# shape test.
fixture 'KEYMAP=en'
[[ -z $(detect) ]] || fail "en is refused; xkeyboard-config defines no such layout" "$(detect)"
fixture 'KEYMAP=abc'
[[ -z $(detect) ]] || fail "a three-letter name that is not a layout is refused" "$(detect)"
pass "a name shaped like a layout is refused unless xkeyboard-config defines it"

fixture 'KEYMAP=es'
[[ $(detect | cut -d'|' -f1) == "es" ]] || fail "a layout the catalogue defines is still accepted" "$(detect)"
pass "a layout the catalogue defines is still accepted"

# The aliases are hand-checked mappings onto real layouts, and the console name
# on the left is deliberately not one: uk is a keymap, gb is the layout.
fixture 'KEYMAP=uk'
[[ $(detect | cut -d'|' -f1) == "gb" ]] || fail "an alias is not measured against the catalogue by its console name" "$(detect)"
pass "an alias still converts, though its own name is no layout"

# Without the catalogue nothing can be verified, so nothing is invented. Saying
# so matters: this is the one path where a correct layout is left unused.
fixture 'KEYMAP=fr'
missing=$(OMARCHY_ARM_VCONSOLE="$test_tmp/vconsole.conf" \
          OMARCHY_ARM_X11_KEYMAP="$test_tmp/00-keyboard.conf" \
          OMARCHY_ARM_XKB_RULES="$test_tmp/absent.lst" omarchy_arm_detect_keyboard 2>"$test_tmp/stderr")
[[ -z $missing ]] || fail "no layout is invented when the catalogue is missing" "$missing"
grep -q "xkeyboard-config" "$test_tmp/stderr" ||
  fail "a missing catalogue says what to install" "$(cat "$test_tmp/stderr")"
pass "a missing catalogue leaves the shipped default and says why"

grep -q 'step "Keyboard layout"' "$ROOT/install.sh" ||
  fail "install.sh runs the keyboard step"
pass "install.sh runs the keyboard step"
