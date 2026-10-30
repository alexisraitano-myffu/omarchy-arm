#!/bin/bash

# Inherit the machine's own keyboard layout.
#
# default/hypr/input.lua reads XKBLAYOUT and XKBVARIANT out of
# /etc/vconsole.conf and falls back to "us". On an ISO install that is enough,
# because the installer asked for a layout and wrote it there. Installing onto
# a machine that is already running, nobody asks: an Arch Linux ARM system set
# up from the command line very often has KEYMAP set and XKBLAYOUT absent, and
# the desktop then comes up in US regardless of the keyboard in front of it.
#
# That failure is quiet and genuinely confusing, because the first thing it
# breaks is the password prompt on the lock screen: the account is fine, the
# password is right, and the letters that reach PAM are not the ones that were
# typed.
#
# So: find what the system already declares, and write it where Omarchy looks.
# Upstream's Lua is left alone.
#
# Honours OMARCHY_ARM_DRY_RUN=1.

OMARCHY_ARM_VCONSOLE="${OMARCHY_ARM_VCONSOLE:-/etc/vconsole.conf}"
OMARCHY_ARM_X11_KEYMAP="${OMARCHY_ARM_X11_KEYMAP:-/etc/X11/xorg.conf.d/00-keyboard.conf}"

# xkeyboard-config's own catalogue of layouts, which is the same data
# libxkbcommon compiles a keymap out of. Overridable so the tests can drive a
# fixture instead of whatever the machine running them happens to ship.
OMARCHY_ARM_XKB_RULES="${OMARCHY_ARM_XKB_RULES:-/usr/share/X11/xkb/rules/base.lst}"

# Console keymap names are not xkb layout names. Most differ only by a suffix
# ("fr-latin9" -> "fr"), which the generic rule below handles; these are the
# ones where the base name itself differs, or where the keymap implies a
# variant. Everything not listed falls through to its own base name.
#
# Format: <console keymap base>:<xkb layout>:<xkb variant>
OMARCHY_ARM_KEYMAP_ALIASES="
uk:gb:
dvorak:us:dvorak
colemak:us:colemak
sg:ch:de
sf:ch:fr
la:latam:
"

omarchy_arm_conf_value() {
  local key="$1" file="$2"

  [[ -r $file ]] || return 0

  sed -n -E "s/^[[:space:]]*${key}=[\"']?([^\"'#[:space:]]*)[\"']?.*/\1/p" "$file" | head -1
}

# XkbLayout "fr" inside an InputClass section.
omarchy_arm_x11_value() {
  local key="$1"

  [[ -r $OMARCHY_ARM_X11_KEYMAP ]] || return 0

  sed -n -E "s/^[[:space:]]*Option[[:space:]]+\"${key}\"[[:space:]]+\"([^\"]*)\".*/\1/p" \
    "$OMARCHY_ARM_X11_KEYMAP" | head -1
}

# The layout section of the rules list is a block of "<name>  <description>"
# lines between a "! layout" header and the next "!" header.
omarchy_arm_xkb_layout_exists() {
  local layout="$1"

  if [[ ! -r $OMARCHY_ARM_XKB_RULES ]]; then
    echo "$OMARCHY_ARM_XKB_RULES is missing, so no layout can be verified;" >&2
    echo "leaving the shipped default. Install xkeyboard-config." >&2
    return 1
  fi

  awk -v want="$layout" '
    /^![[:space:]]*layout/ { in_layouts = 1; next }
    /^!/ { in_layouts = 0 }
    in_layouts && $1 == want { found = 1; exit }
    END { exit !found }
  ' "$OMARCHY_ARM_XKB_RULES"
}

omarchy_arm_keymap_to_xkb() {
  local keymap="$1" base alias_line alias_base alias_layout alias_variant

  # Strip the encoding or hardware suffix: fr-latin9, de-latin1-nodeadkeys.
  base="${keymap%%-*}"

  while read -r alias_line; do
    [[ -n $alias_line ]] || continue
    IFS=: read -r alias_base alias_layout alias_variant <<<"$alias_line"
    if [[ $base == "$alias_base" ]]; then
      printf '%s|%s\n' "$alias_layout" "$alias_variant"
      return 0
    fi
  done <<<"$OMARCHY_ARM_KEYMAP_ALIASES"

  # Ask xkeyboard-config whether that name is a layout, rather than deciding
  # from its shape. A console keymap can be two or three letters and still be
  # no layout at all -- "en" is the one people reach for -- and a name that
  # only looks right is worse than no name: libxkbcommon fails to compile the
  # keymap, Hyprland comes up without one, and the lock screen then rejects a
  # password that was typed correctly. Falling through leaves the shipped "us",
  # which at least types.
  if omarchy_arm_xkb_layout_exists "$base"; then
    printf '%s|\n' "$base"
  fi
}

# Prints "<layout>|<variant>|<source>", or nothing when the system declares no
# layout of its own.
#
# Pipe-separated, not tab-separated: tab is IFS whitespace, so `read` collapses
# a run of them into one delimiter and an empty variant silently shifts every
# later field left. That put the source string into the variant.
omarchy_arm_detect_keyboard() {
  local layout variant

  # Already where Omarchy reads it: nothing to do.
  layout=$(omarchy_arm_conf_value XKBLAYOUT "$OMARCHY_ARM_VCONSOLE")
  if [[ -n $layout ]]; then
    variant=$(omarchy_arm_conf_value XKBVARIANT "$OMARCHY_ARM_VCONSOLE")
    printf '%s|%s|%s\n' "$layout" "$variant" "$OMARCHY_ARM_VCONSOLE"
    return 0
  fi

  # The X11 config is what localectl set-x11-keymap writes, and it is the
  # authoritative xkb answer when it exists.
  layout=$(omarchy_arm_x11_value XkbLayout)
  if [[ -n $layout ]]; then
    variant=$(omarchy_arm_x11_value XkbVariant)
    printf '%s|%s|%s\n' "$layout" "$variant" "$OMARCHY_ARM_X11_KEYMAP"
    return 0
  fi

  # Last resort: the console keymap, which a command-line Arch install almost
  # always sets even when it sets nothing else.
  local keymap
  keymap=$(omarchy_arm_conf_value KEYMAP "$OMARCHY_ARM_VCONSOLE")
  if [[ -n $keymap ]]; then
    local converted
    converted=$(omarchy_arm_keymap_to_xkb "$keymap")
    if [[ -n $converted ]]; then
      IFS='|' read -r layout variant <<<"$converted"
      printf '%s|%s|%s\n' "$layout" "$variant" "KEYMAP=$keymap in $OMARCHY_ARM_VCONSOLE"
      return 0
    fi
  fi
}

omarchy_arm_apply_keyboard() {
  local dry="${OMARCHY_ARM_DRY_RUN:-0}"
  local detected layout variant source

  detected=$(omarchy_arm_detect_keyboard)

  if [[ -z $detected ]]; then
    echo "This machine declares no keyboard layout, so the desktop will use us."
    echo "Set one with: sudo localectl set-x11-keymap <layout> [model] [variant]"
    return 0
  fi

  IFS='|' read -r layout variant source <<<"$detected"

  if [[ $source == "$OMARCHY_ARM_VCONSOLE" ]]; then
    echo "Keyboard layout: $layout${variant:+ ($variant)}, already where Omarchy reads it."
    return 0
  fi

  echo "Keyboard layout: $layout${variant:+ ($variant)}, from $source."
  echo "Recording it as XKBLAYOUT in $OMARCHY_ARM_VCONSOLE, which is where"
  echo "Omarchy's Hyprland config reads it from."

  if (( dry )); then
    echo "[dry-run] write XKBLAYOUT=$layout${variant:+ and XKBVARIANT=$variant} to $OMARCHY_ARM_VCONSOLE"
    return 0
  fi

  sudo mkdir -p "$(dirname "$OMARCHY_ARM_VCONSOLE")"
  sudo touch "$OMARCHY_ARM_VCONSOLE"
  printf 'XKBLAYOUT=%s\n' "$layout" | sudo tee -a "$OMARCHY_ARM_VCONSOLE" >/dev/null
  [[ -n $variant ]] && printf 'XKBVARIANT=%s\n' "$variant" | sudo tee -a "$OMARCHY_ARM_VCONSOLE" >/dev/null

  return 0
}
