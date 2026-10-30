#!/bin/bash

# Omarchy ARM64 installer.
#
# Upstream Omarchy is installed from an ISO that pacstraps a fixed package set
# onto a fresh x86_64 disk. That ISO does not exist for aarch64, and the
# packages it would pull are not built for it, so this fork installs onto an
# Arch Linux ARM system that is already running:
#
#   - an Apple Silicon Mac under Asahi's Arch Linux ARM port
#   - a Raspberry Pi 5 under Arch Linux ARM
#   - an aarch64 virtual machine under Arch Linux ARM
#
# Run it as your normal user from a checkout of this repository:
#
#   ./install.sh --dry-run     # print the whole plan, change nothing
#   ./install.sh
#
# See docs/arm64-port.md for what differs from upstream and why.

set -euo pipefail

CHECKOUT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

DRY_RUN=0
ASSUME_YES=0
SKIP_PACKAGES=0
WITH_AUR=0
NO_AUR=0
LINK_CHECKOUT=0
TARGET="/usr/share/omarchy"
FORCED_PLATFORM=""

RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

usage() {
  cat <<USAGE
Usage: ./install.sh [options]

Installs Omarchy onto a running Arch Linux ARM (aarch64) system.

Options:
  --dry-run          Print every action without changing anything
  -y, --yes          Do not prompt for confirmation
  --skip-packages    Leave package installation to you entirely
  --with-aur         Also install the packages that only exist in the AUR.
                     Off by default: on aarch64 every one of them is compiled
                     on this machine, and one pulls in a Zig and LLVM
                     toolchain that needs several GB and a long build
  --no-aur           Keep every AUR package out, including the three the
                     desktop needs (the terminal launcher and mise, which
                     installs the AI CLIs). Leaves a degraded desktop
  --target DIR       Where Omarchy is installed (default: $TARGET)
  --link             Point the target at this checkout with a symlink instead
                     of copying it, for working on the fork itself
  --profile NAME     Override hardware detection: apple-silicon,
                     raspberry-pi-5, raspberry-pi or generic-aarch64
  -h, --help         Show this message
USAGE
}

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    --skip-packages) SKIP_PACKAGES=1; shift ;;
    --with-aur) WITH_AUR=1; shift ;;
    --no-aur) WITH_AUR=0; NO_AUR=1; shift ;;
    --link) LINK_CHECKOUT=1; shift ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    --profile) FORCED_PLATFORM="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

step() { printf '\n%s==> %s%s\n' "$BOLD$BLUE" "$1" "$RESET"; }
say() { printf '    %s\n' "$1"; }
ok() { printf '    %s%s%s\n' "$GREEN" "$1" "$RESET"; }
warn() { printf '    %s%s%s\n' "$YELLOW" "$1" "$RESET"; }
die() { printf '\n%sError: %s%s\n' "$RED" "$1" "$RESET" >&2; exit 1; }

# Every mutating command goes through run(), which is what makes --dry-run
# honest: there is no second code path that could drift from the real one.
run() {
  if (( DRY_RUN )); then
    # ${*@Q} keeps a path with a space in it readable as the single argument
    # it actually is, instead of printing a command nobody could paste back.
    printf '    %s[dry-run]%s %s\n' "$YELLOW" "$RESET" "${*@Q}"
  else
    "$@"
  fi
}

bootstrap_aur_helper() {
  command -v yay >/dev/null && return 0
  command -v paru >/dev/null && return 0

  say "No AUR helper found; building yay from source first."
  run sudo pacman -S --needed --noconfirm base-devel git go

  # mktemp has to run for real even in a dry run, or the commands below would
  # be printed with an empty path and read as nonsense.
  local build_dir
  build_dir=$(mktemp -d)
  run git clone --depth 1 https://aur.archlinux.org/yay.git "$build_dir/yay"
  run bash -c "cd '$build_dir/yay' && makepkg -si --noconfirm"
  rm -rf "$build_dir"
}

confirm() {
  (( ASSUME_YES || DRY_RUN )) && return 0

  local reply
  read -r -p "    $1 [y/N] " reply
  [[ $reply == [yY] || $reply == [yY][eE][sS] ]]
}

# Read a manifest under install/arm/, dropping comments and blank lines and
# keeping only the first field of each line.
manifest() {
  local file="$CHECKOUT/install/arm/$1"

  [[ -f $file ]] || return 0
  sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$file" | awk '{print $1}'
}

########################################################################
step "Preflight"
########################################################################

(( BASH_VERSINFO[0] >= 5 )) ||
  die "Omarchy needs bash 5 or newer; this shell is $BASH_VERSION."

(( EUID != 0 )) ||
  die "Run install.sh as your normal user, not as root. It calls sudo where it needs to."

export PATH="$CHECKOUT/bin:$PATH"

arch=$(uname -m)
if [[ $arch != "aarch64" ]]; then
  die "This fork installs on aarch64 only; this machine reports '$arch'.
       Upstream Omarchy (github.com/basecamp/omarchy) is what you want on x86_64."
fi
ok "Architecture: $arch"

# Overridable so the test suite can drive this against a fixture instead of
# the machine it runs on.
os_release="${OMARCHY_OS_RELEASE:-/etc/os-release}"
[[ -r $os_release ]] || die "$os_release is missing; cannot identify this distribution."
# shellcheck disable=SC1091
. "$os_release"
distro_id="${ID:-unknown}"
distro_like="${ID_LIKE:-}"

# Arch Linux ARM reports ID=archarm; a machine set up from Arch's own aarch64
# instructions may report ID=arch, and derivatives put arch in ID_LIKE.
case " $distro_id $distro_like " in
  *" arch "*|*" archarm "*)
    ok "Distribution: ${PRETTY_NAME:-$distro_id}"
    ;;
  *)
    die "This fork targets Arch Linux ARM; this machine reports '${PRETTY_NAME:-$distro_id}'.
       Porting Omarchy's 400-odd commands off pacman is a different project --
       see docs/arm64-port.md for why that road was not taken."
    ;;
esac

command -v pacman >/dev/null || die "pacman is not installed; this is not an Arch-based system."
command -v sudo >/dev/null || die "sudo is not installed."

# A pacstrapped Arch Linux ARM system can arrive without its own keyring, in
# which case every single package below would fail verification. Catch it here
# rather than 200 signature errors into the install.
source "$CHECKOUT/install/arm/keyring.sh"
if ! OMARCHY_ARM_DRY_RUN="$DRY_RUN" omarchy_arm_keyring_repair; then
  die "pacman cannot verify Arch Linux ARM packages on this machine."
fi

if [[ -n $FORCED_PLATFORM ]]; then
  platform="$FORCED_PLATFORM"
  warn "Platform forced to '$platform' (detection said '$(omarchy-hw-platform)')"
else
  platform=$(omarchy-hw-platform)
fi

case "$platform" in
  apple-silicon)
    ok "Platform: Apple Silicon Mac (Asahi)"
    ;;
  raspberry-pi-5)
    ok "Platform: Raspberry Pi 5"
    ;;
  raspberry-pi)
    ok "Platform: Raspberry Pi (pre-5)"
    warn "Only the Pi 5 is tested. Older Pis have no Vulkan-capable GPU for Hyprland."
    ;;
  generic-aarch64)
    ok "Platform: generic aarch64 (virtual machine or unrecognised board)"
    ;;
  *)
    die "Unknown platform '$platform'."
    ;;
esac

(( DRY_RUN )) && warn "Dry run: nothing on this machine will be changed."

########################################################################
step "Package plan"
########################################################################

declare -a repo_pkgs=() aur_pkgs=() aur_required_pkgs=() unavailable_pkgs=() unknown_pkgs=()

if (( SKIP_PACKAGES )); then
  warn "--skip-packages: package installation skipped entirely."
else
  declare -A replace=() excluded=() known_aur=() known_aur_required=() known_unavailable=()

  while read -r from to; do
    [[ -n ${from:-} && -n ${to:-} ]] && replace[$from]="$to"
  done < <(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$CHECKOUT/install/arm/packages.replace" 2>/dev/null || true)

  while read -r pkg; do excluded[$pkg]=1; done < <(manifest packages.exclude)
  while read -r pkg; do known_aur[$pkg]=1; done < <(manifest packages.aur)
  while read -r pkg; do known_aur_required[$pkg]=1; done < <(manifest packages.aur-required)
  while read -r pkg; do known_unavailable[$pkg]=1; done < <(manifest packages.unavailable)

  # pacman -Si only knows what the last sync knew, so an unsynced machine would
  # report the entire package set as missing.
  sync_dir="${OMARCHY_PACMAN_SYNC_DIR:-/var/lib/pacman/sync}"
  if [[ ! -d $sync_dir ]] || [[ -z $(ls -A "$sync_dir" 2>/dev/null) ]]; then
    warn "The package databases have never been synced."
    run sudo pacman -Sy --noconfirm
  fi

  while read -r pkg; do
    [[ -n ${excluded[$pkg]:-} ]] && continue
    [[ -n ${replace[$pkg]:-} ]] && pkg="${replace[$pkg]}"

    if pacman -Si "$pkg" &>/dev/null; then
      repo_pkgs+=("$pkg")
    elif [[ -n ${known_aur_required[$pkg]:-} ]]; then
      aur_required_pkgs+=("$pkg")
    elif [[ -n ${known_aur[$pkg]:-} ]]; then
      aur_pkgs+=("$pkg")
    elif [[ -n ${known_unavailable[$pkg]:-} ]]; then
      unavailable_pkgs+=("$pkg")
    else
      unknown_pkgs+=("$pkg")
    fi
  done < <(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$CHECKOUT/install/omarchy-base.packages")

  say "From the configured repositories: ${#repo_pkgs[@]}"
  aur_note=" (skipped; --with-aur installs them)"
  (( WITH_AUR )) && aur_note=" (compiled on this machine)"
  say "Only in the AUR, needed:          ${#aur_required_pkgs[@]}"
  say "Only in the AUR, optional:        ${#aur_pkgs[@]}$aur_note"
  say "No aarch64 source at all:         ${#unavailable_pkgs[@]}"

  if (( ${#unknown_pkgs[@]} > 0 )); then
    warn "Not in the repositories and not in any manifest: ${unknown_pkgs[*]}"
    warn "Add them to install/arm/packages.{aur,unavailable,replace} so this stays honest."
  fi

  if (( ${#unavailable_pkgs[@]} > 0 )); then
    say ""
    say "These are skipped; the desktop comes up without them:"
    say "  ${unavailable_pkgs[*]}"
  fi

  # Packages the ISO installs from omarchy-other.packages. They are not in the
  # base list, so the loop above never sees them, and their absence is only
  # visible once the machine is running: no compressed swap, no PulseAudio
  # server. See install/arm/packages.extra for the reason on each one.
  declare -a extra_pkgs=()
  while read -r pkg _; do
    [[ -n $pkg ]] || continue
    if pacman -Si "$pkg" &>/dev/null; then
      extra_pkgs+=("$pkg")
      repo_pkgs+=("$pkg")
    else
      warn "$pkg is named in packages.extra but no repository has it."
    fi
  done < <(manifest packages.extra)

  (( ${#extra_pkgs[@]} > 0 )) && say "Installed by the ISO on x86_64:   ${#extra_pkgs[@]} (${extra_pkgs[*]})"

  say ""
  confirm "Install ${#repo_pkgs[@]} packages now?" || die "Cancelled."

  run sudo pacman -S --needed --noconfirm "${repo_pkgs[@]}"
  ok "Repository packages installed."

  # The needed ones go in now, not with the optional set at the end: the
  # firewall leaf uses ufw-docker during system setup, and install/user/mise.sh
  # uses mise during user setup. Waiting until after both would install them
  # too late to be used.
  if (( ${#aur_required_pkgs[@]} > 0 )); then
    if (( WITH_AUR )) || (( ! NO_AUR )); then
      bootstrap_aur_helper
      for pkg in "${aur_required_pkgs[@]}"; do
        if ! run omarchy-pkg-aur-add "$pkg"; then
          warn "$pkg failed to build on aarch64; continuing without it."
          unavailable_pkgs+=("$pkg")
        fi
      done
      ok "Needed AUR packages installed."
    else
      warn "--no-aur: skipping ${aur_required_pkgs[*]}"
      warn "Without xdg-terminal-exec no terminal opens, and without mise the"
      warn "AI CLIs and dev tools are not installed."
    fi
  fi

fi

########################################################################
step "Deploy Omarchy to $TARGET"
########################################################################

# Hyprland reloads its config as soon as a file it watches changes. From here
# on this script rewrites the tree those files live in, the files themselves,
# and the ones under ~/.config -- so a reload can land halfway through and find
# a config that does not parse yet, which drops the session into emergency
# mode: no keybindings, and no keyboard layout, so the lock screen then refuses
# the password the user is typing.
#
# Upstream has exactly this problem when the omarchy-settings package upgrades,
# and solves it with two pacman hooks around the transaction. There is no
# package and no transaction here, so call the same command directly. resume
# reloads the config on the way out, which is what puts the session back on the
# new files.
reload_guard() {
  local action="$1"

  [[ -x $CHECKOUT/bin/omarchy-hyprland-reload-guard ]] || return 0
  run sudo "$CHECKOUT/bin/omarchy-hyprland-reload-guard" "$action" || true
}

reload_guard pause
trap 'reload_guard resume' EXIT


if [[ $CHECKOUT == "$TARGET" ]]; then
  ok "Already running from $TARGET."
elif (( LINK_CHECKOUT )); then
  run sudo rm -rf "$TARGET"
  run sudo mkdir -p "$(dirname "$TARGET")"
  run sudo ln -sfn "$CHECKOUT" "$TARGET"
  ok "$TARGET now points at $CHECKOUT."
else
  # A running session reads $TARGET the whole time: Hyprland dofiles
  # bootstrap.lua out of it on every config reload, and all 434 omarchy
  # commands in /usr/bin are symlinks into it. Moving the old tree aside and
  # then copying 1600 files into place leaves every one of those broken for the
  # length of the copy. A reload landing in that window drops Hyprland into
  # emergency mode: no keybindings, and no keyboard layout either, so the lock
  # screen then rejects a password typed on the layout the user actually has.
  # Stage the new tree beside the old one and swap it in with renames, so the
  # window is two syscalls rather than a file copy.
  staging="$TARGET.omarchy-arm.new"

  run sudo rm -rf "$staging"
  run sudo mkdir -p "$staging"
  run sudo cp -a "$CHECKOUT/." "$staging/"
  run sudo rm -rf "$staging/.git"

  # On x86 this tree belongs to the omarchy package, so it is root-owned. Here
  # it is a copy of a user's checkout, and root runs scripts out of it
  # (omarchy-apply-system, the settings step, every command in /usr/bin is a
  # symlink into it). Leaving it writable by that user would make all of that
  # editable by anyone who can write the checkout.
  run sudo chown -R root:root "$staging"

  if [[ -L $TARGET ]]; then
    run sudo rm -f "$TARGET"
  elif [[ -e $TARGET ]]; then
    run sudo rm -rf "$TARGET.omarchy-arm.bak"
    run sudo mv "$TARGET" "$TARGET.omarchy-arm.bak"
    say "Previous install moved to $TARGET.omarchy-arm.bak"
  fi

  run sudo mv "$staging" "$TARGET"
  ok "Checkout copied to $TARGET."
fi

# /etc/omarchy.conf is what every Omarchy entry point reads to resolve
# $OMARCHY_PATH, so it is what makes a non-default target actually work.
run sudo mkdir -p /etc
if (( DRY_RUN )); then
  printf '    %s[dry-run]%s write /etc/omarchy.conf: export OMARCHY_PATH="%s"\n' "$YELLOW" "$RESET" "$TARGET"
else
  printf 'export OMARCHY_PATH="%s"\n' "$TARGET" | sudo tee /etc/omarchy.conf >/dev/null
fi

export OMARCHY_PATH="$TARGET"
export OMARCHY_INSTALL="$TARGET/install"

########################################################################
step "Install the files the omarchy-settings package would own"
########################################################################

say "There is no aarch64 build of omarchy-settings, so its file map is"
say "replayed straight from the checkout. See install/arm/settings.sh."

if (( DRY_RUN )); then
  OMARCHY_ARM_DRY_RUN=1 OMARCHY_PATH="$CHECKOUT" bash "$CHECKOUT/install/arm/settings.sh"
else
  sudo OMARCHY_PATH="$TARGET" bash "$TARGET/install/arm/settings.sh"
fi

########################################################################
step "Keyboard layout"
########################################################################

source "$CHECKOUT/install/arm/keyboard.sh"
OMARCHY_ARM_DRY_RUN="$DRY_RUN" omarchy_arm_apply_keyboard

########################################################################
step "Locale"
########################################################################

source "$CHECKOUT/install/arm/locale.sh"
OMARCHY_ARM_DRY_RUN="$DRY_RUN" omarchy_arm_apply_locale

########################################################################
step "Shipped defaults for $USER"
########################################################################

# /etc/skel above only reaches users created after it. This machine's user
# already existed, so the defaults have to be copied in explicitly.
source "$CHECKOUT/install/arm/seed-home.sh"
OMARCHY_ARM_DRY_RUN="$DRY_RUN" omarchy_arm_seed_home "$HOME"

########################################################################
step "System setup"
########################################################################

run sudo -E "$TARGET/bin/omarchy-apply-system" --install-user "$USER" --first-install

########################################################################
step "Remote access"
########################################################################

source "$CHECKOUT/install/arm/firewall-ssh.sh"
OMARCHY_ARM_DRY_RUN="$DRY_RUN" omarchy_arm_keep_ssh_reachable

########################################################################
step "Login screen"
########################################################################

source "$CHECKOUT/install/arm/login.sh"
OMARCHY_ARM_DRY_RUN="$DRY_RUN" omarchy_arm_seed_sddm_state "$USER"

########################################################################
step "User setup"
########################################################################

# --force, not --first-install. The latter makes omarchy-provision-user set
# OMARCHY_SETUP_CONTEXT=iso-chroot, and the leaves then look for tarballs the
# ISO bundles under /opt/packages, which does not exist on a running machine:
# install/user/mise-work.sh fails outright on the Node one.
#
# The other thing --first-install does is mark the shipped migrations complete.
# install/arm/settings.sh already writes those markers into /etc/skel, and the
# seeding step copies them in, so nothing replays.
run "$TARGET/bin/omarchy-provision-user" --force

########################################################################
step "AUR packages"
########################################################################

# Deliberately last, and off unless asked for.
#
# On x86_64 these arrive as prebuilt binaries. On aarch64 every one of them is
# compiled here, and the chain is not shallow: herdr pulls zig0.15, which
# rebuilds Zig against LLVM 20. On a first run that filled a 15 GB disk and was
# still compiling long after the desktop itself was ready.
#
# Running it after the desktop is provisioned means a machine that runs out of
# space or patience here still has a working Omarchy, and losing an optional
# app is the whole cost.
if (( SKIP_PACKAGES )) || (( ${#aur_pkgs[@]} == 0 )); then
  :
elif (( ! WITH_AUR )); then
  say "Skipped: ${aur_pkgs[*]}"
  say "Install them later with ./install.sh --with-aur --skip-packages,"
  say "or one at a time with omarchy pkg aur add <name>."
else
  bootstrap_aur_helper

  warn "Compiling ${#aur_pkgs[@]} AUR packages. This is the slow part."
  # One at a time: a package that will not build on aarch64 should cost that
  # package, not the run.
  for pkg in "${aur_pkgs[@]}"; do
    if ! run omarchy-pkg-aur-add "$pkg"; then
      warn "$pkg failed to build on aarch64; continuing without it."
      unavailable_pkgs+=("$pkg")
    fi
  done
fi

########################################################################
step "Done"
########################################################################

reload_guard resume
trap - EXIT


if (( ${#unavailable_pkgs[@]} > 0 )); then
  warn "Installed without these, which have no aarch64 build:"
  warn "  ${unavailable_pkgs[*]}"
  say "docs/arm64-port.md records where each of them comes from."
fi

if (( DRY_RUN )); then
  ok "Dry run complete. Nothing was changed."
else
  ok "Omarchy is installed."
  say "Enable the display manager and reboot into the session:"
  say "  sudo systemctl enable sddm.service && sudo reboot"
fi
