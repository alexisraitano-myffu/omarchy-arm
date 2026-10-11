#!/bin/bash

# Tell the greeter who is logging in.
#
# Omarchy's SDDM theme asks for a password only. The username comes from
# `userModel.lastUser`, which SDDM reads from /var/lib/sddm/state.conf. On
# x86_64 the ISO's orchestrator writes that file for the user it just created
# (omarchy-iso, configure_login), so the first greeter already knows them.
#
# This installer runs on a machine that was never installed from that ISO, so
# the file does not exist. The greeter then logs in as the empty user, and
# every password fails with "User not known to the underlying authentication
# module" -- which reads like a wrong password, not a missing file. Measured on
# an aarch64 VM under Parallels, 2026-10-11.
#
# Seed the same state the ISO would have. Not [Autologin]: upstream reserves
# that for encrypted installs, where the LUKS prompt is the auth boundary, and
# a machine installed over SSH has no reason to skip its login screen.
#
# Honours OMARCHY_ARM_DRY_RUN=1.

omarchy_arm_seed_sddm_state() {
  local dry="${OMARCHY_ARM_DRY_RUN:-0}"
  local user="${1:-$USER}"
  local state_dir="${OMARCHY_ARM_SDDM_STATE_DIR:-/var/lib/sddm}"
  local state="$state_dir/state.conf"
  local session="omarchy.desktop"

  if [[ -r $state ]] && grep -qE "^User=.+" "$state"; then
    echo "SDDM already remembers a user; leaving $state alone."
    return 0
  fi

  echo "SDDM has no last user, so the greeter would log in as nobody."
  echo "Seeding $state with User=$user Session=$session."

  if (( dry )); then
    echo "[dry-run] sudo install -d -m 750 -o sddm -g sddm $state_dir"
    echo "[dry-run] write $state: [Last] Session=$session User=$user"
    return 0
  fi

  sudo install -d -m 750 -o sddm -g sddm "$state_dir"
  printf '[Last]\nSession=%s\nUser=%s\n' "$session" "$user" |
    sudo install -m 600 -o sddm -g sddm /dev/stdin "$state"
}
