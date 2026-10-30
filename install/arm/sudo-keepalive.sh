#!/bin/bash

# Hold the sudo timestamp open for the whole install.
#
# sudo forgets an authentication after five minutes by default. Installing the
# repository packages takes longer than that on aarch64, and the AUR bootstrap
# immediately after it runs makepkg, which refuses to run as root and calls
# sudo itself to install what it built. By then the timestamp has expired, so
# makepkg prompts -- from inside a `bash -c 'cd ... && makepkg -si'`, with the
# installer's own output scrolling over it. On a Raspberry Pi installed over
# SSH that reads as an install that hung, and the only clue is that nothing
# has moved for an hour.
#
# So: authenticate once, up front, where a prompt is expected and legible, and
# refresh the timestamp in the background until the run is over.
#
# Honours OMARCHY_ARM_DRY_RUN=1: a dry run authenticates nothing.

OMARCHY_ARM_SUDO_KEEPALIVE_PID=""

omarchy_arm_sudo_keepalive_start() {
  local dry="${OMARCHY_ARM_DRY_RUN:-0}"
  local interval="${OMARCHY_ARM_SUDO_INTERVAL:-60}"

  if (( dry )); then
    echo "[dry-run] sudo -v, then refresh the timestamp every ${interval}s"
    return 0
  fi

  [[ -z $OMARCHY_ARM_SUDO_KEEPALIVE_PID ]] || return 0

  echo "Asking for your password once now, so nothing prompts for it again"
  echo "an hour into the package install with no terminal watching."
  sudo -v || return 1

  # -n on the refresh: a timestamp invalidated from another terminal must end
  # this loop, not block it on a prompt nobody is reading. The install then
  # fails on its next real sudo, which is a visible failure rather than a
  # silent stall.
  while sudo -n -v 2>/dev/null; do
    sleep "$interval"
  done &

  OMARCHY_ARM_SUDO_KEEPALIVE_PID=$!
}

omarchy_arm_sudo_keepalive_stop() {
  [[ -n $OMARCHY_ARM_SUDO_KEEPALIVE_PID ]] || return 0

  # kill and wait together, with the shell's own job notification silenced:
  # left to notice on its own, bash prints "Terminated" over whatever the
  # install is saying at the time.
  { kill "$OMARCHY_ARM_SUDO_KEEPALIVE_PID" && wait "$OMARCHY_ARM_SUDO_KEEPALIVE_PID"; } 2>/dev/null || true
  OMARCHY_ARM_SUDO_KEEPALIVE_PID=""

  return 0
}
