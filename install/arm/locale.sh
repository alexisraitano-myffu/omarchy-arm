#!/bin/bash

# Give the machine a UTF-8 locale when it has none.
#
# The ISO installer picks a locale and generates it. Installing onto a machine
# that is already running, nobody does: the stock Arch Linux ARM image ships
# /etc/locale.conf with LANG=C and nothing uncommented in /etc/locale.gen. The
# desktop then runs in the C locale. Progress bars and box drawing come out as
# mojibake ("âââ"), the shell prints glyph escapes literally, and SDDM warns
# that the locale is ANSI_X3.4-1968.
#
# So: if LANG is unset, C or POSIX, generate OMARCHY_ARM_LOCALE (en_US.UTF-8
# unless set) and make it the system LANG. A locale someone already chose is
# left alone.
#
# Honours OMARCHY_ARM_DRY_RUN=1.

OMARCHY_ARM_LOCALE_CONF="${OMARCHY_ARM_LOCALE_CONF:-/etc/locale.conf}"
OMARCHY_ARM_LOCALE_GEN="${OMARCHY_ARM_LOCALE_GEN:-/etc/locale.gen}"
OMARCHY_ARM_LOCALE="${OMARCHY_ARM_LOCALE:-en_US.UTF-8}"

# Prints the LANG the system declares, or nothing.
omarchy_arm_current_lang() {
  [[ -r $OMARCHY_ARM_LOCALE_CONF ]] || return 0
  sed -n 's/^[[:space:]]*LANG=//p' "$OMARCHY_ARM_LOCALE_CONF" | tail -n1 | tr -d "\"'"
}

# True when the declared LANG is a real choice rather than the image default.
omarchy_arm_lang_is_set() {
  case "$(omarchy_arm_current_lang)" in
    "" | C | POSIX) return 1 ;;
    *) return 0 ;;
  esac
}

omarchy_arm_apply_locale() {
  local dry="${OMARCHY_ARM_DRY_RUN:-0}"
  local locale="$OMARCHY_ARM_LOCALE"
  local charset="${locale#*.}"

  if omarchy_arm_lang_is_set; then
    echo "Locale: $(omarchy_arm_current_lang), already set."
    return 0
  fi

  echo "This machine has no locale (LANG=$(omarchy_arm_current_lang)), so the desktop would run in C."
  echo "Generating $locale and making it the system locale."
  echo "Set OMARCHY_ARM_LOCALE to pick another, or change it later in $OMARCHY_ARM_LOCALE_CONF."

  if (( dry )); then
    echo "[dry-run] enable '$locale $charset' in $OMARCHY_ARM_LOCALE_GEN, run locale-gen"
    echo "[dry-run] write LANG=$locale to $OMARCHY_ARM_LOCALE_CONF"
    return 0
  fi

  # locale.gen lists every locale commented out; uncomment ours, or add it.
  if grep -q "^#[[:space:]]*${locale//./\\.}[[:space:]]" "$OMARCHY_ARM_LOCALE_GEN" 2>/dev/null; then
    sudo sed -i "s/^#[[:space:]]*\(${locale//./\\.}[[:space:]]\)/\1/" "$OMARCHY_ARM_LOCALE_GEN"
  elif ! grep -q "^${locale//./\\.}[[:space:]]" "$OMARCHY_ARM_LOCALE_GEN" 2>/dev/null; then
    printf '%s %s\n' "$locale" "$charset" | sudo tee -a "$OMARCHY_ARM_LOCALE_GEN" >/dev/null
  fi
  sudo locale-gen

  printf 'LANG=%s\n' "$locale" | sudo tee "$OMARCHY_ARM_LOCALE_CONF" >/dev/null

  return 0
}
