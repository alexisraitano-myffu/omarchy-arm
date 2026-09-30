#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

all="$ROOT/install/hardware/all.sh"
post="$ROOT/install/post-install/pacman.sh"

grep -q 'source "\$OMARCHY_INSTALL/arm/platform.sh"' "$all" ||
  fail "install/hardware/all.sh has the gating helpers in scope"
pass "install/hardware/all.sh has the gating helpers in scope"

# Each of these installs a driver, firmware or kernel that has no aarch64
# build. One of them slipping back to a bare run_logged is an install that
# fails on the target hardware, not one that degrades.
x86_only=(
  hardware/nvidia.sh
  hardware/vulkan.sh
  hardware/intel/video-acceleration.sh
  hardware/intel/lpmd.sh
  hardware/intel/thermald.sh
  hardware/intel/ptl-kernel.sh
  hardware/intel/ipu7-camera.sh
  hardware/intel/fred.sh
  hardware/intel/fix-wifi7-eht.sh
  hardware/intel/sof-firmware.sh
  hardware/apple/fix-t2.sh
  hardware/apple/fix-spi-keyboard.sh
  hardware/apple/fix-suspend-nvme.sh
  hardware/apple/fix-brcmfmac-supplicant.sh
  hardware/pacman.sh
)

for leaf in "${x86_only[@]}"; do
  grep -q "run_logged_x86 \"\$OMARCHY_INSTALL/$leaf\"" "$all" ||
    fail "$leaf is gated to x86_64" "$(grep -n "$leaf" "$all")"
done
pass "every x86-only hardware leaf is gated"

for leaf in hardware/arm/vulkan.sh hardware/arm/apple-silicon.sh hardware/arm/raspberry-pi.sh hardware/arm/cix-sky1.sh; do
  grep -q "run_logged_arm \"\$OMARCHY_INSTALL/$leaf\"" "$all" ||
    fail "$leaf runs on aarch64 only"
  [[ -f $ROOT/install/$leaf ]] || fail "$leaf exists"
done
pass "the ARM hardware leaves are wired and present"

# snapper is wired to limine on x86 (config/all.sh enables
# limine-snapper-sync.service alongside it) and snapper itself is not in the
# ARM package set, so the leaf would abort omarchy-apply-system on the very
# first ARM install: it runs under set -e, and `snapper create-config` fails
# when the command does not exist.
grep -q 'run_logged_x86 "\$OMARCHY_INSTALL/config/snapper.sh"' "$ROOT/install/config/all.sh" ||
  fail "the snapper leaf is gated to x86_64" "$(cat "$ROOT/install/config/all.sh")"
grep -q 'source "\$OMARCHY_INSTALL/arm/platform.sh"' "$ROOT/install/config/all.sh" ||
  fail "install/config/all.sh has the gating helpers in scope"
pass "the snapper leaf is gated to x86_64"

# The single most destructive thing this fork prevents: upstream's
# post-install step replaces /etc/pacman.conf with one that points at x86-only
# repositories, which would leave an ARM machine unable to resolve a package.
grep -q "if omarchy_arm_is_arm; then" "$post" ||
  fail "the pacman.conf restore is gated on ARM" "$(cat "$post")"
grep -q 'source "\$OMARCHY_INSTALL/arm/pacman.sh"' "$post" ||
  fail "ARM gets its own pacman configuration step"
pass "the x86 pacman.conf restore cannot run on ARM"

# install/arm/pacman.sh edits options in place; it must never write a Server
# line, because the host's mirrors are the only ones that work.
! grep -qE '^\s*(Server|Include)\s*=' "$ROOT/install/arm/pacman.sh" ||
  fail "the ARM pacman step leaves the host's repositories alone" "$(grep -nE '^\s*(Server|Include)' "$ROOT/install/arm/pacman.sh")"
pass "the ARM pacman step leaves the host's repositories alone"

grep -q 'multilib' "$ROOT/install/arm/pacman.sh" ||
  fail "the ARM pacman step removes [multilib]"
grep -q 'omarchy\\\]' "$ROOT/install/arm/pacman.sh" ||
  grep -q '\[omarchy\]' "$ROOT/install/arm/pacman.sh" ||
  fail "the ARM pacman step removes [omarchy]"
pass "the ARM pacman step removes the two x86-only repositories"

# ufw-docker is only in the AUR, which this fork does not install by default.
# Ungated, command -v returns nothing, the sed inside the leaf reads an empty
# path, and the whole of omarchy-apply-system aborts on a Docker convenience
# rule -- which is exactly what happened on the first real install.
grep -q 'if command -v ufw-docker >/dev/null; then' "$ROOT/install/config/firewall.sh" ||
  fail "the firewall leaf tolerates a missing ufw-docker" "$(cat "$ROOT/install/config/firewall.sh")"
pass "the firewall leaf tolerates a missing ufw-docker"

# Same leaf arms a deny-everything firewall for the next boot. On a headless
# Pi that is a machine you can only recover with a keyboard and a monitor.
grep -q 'omarchy_arm_keep_ssh_reachable' "$ROOT/install.sh" ||
  fail "install.sh keeps SSH reachable when it is itself running over SSH"
grep -q 'SSH_CONNECTION' "$ROOT/install/arm/firewall-ssh.sh" ||
  fail "the SSH guard only fires for a remote install"
grep -q "grep -q '\^ENABLED=yes'" "$ROOT/install/arm/firewall-ssh.sh" ||
  fail "the SSH guard only fires when the firewall is actually armed"
pass "SSH stays reachable on a machine installed remotely"

# mise only exists in the AUR for aarch64, and this fork does not install the
# AUR by default. Two user leaves are built entirely around it; ungated, the
# first one aborts omarchy-provision-user with "mise: command not found".
grep -q 'run_logged_cmd mise "\$OMARCHY_INSTALL/user/mise-work.sh"' "$ROOT/install/user/all.sh" ||
  fail "the mise leaves are gated on mise being installed" "$(cat "$ROOT/install/user/all.sh")"
grep -q 'run_logged_cmd mise "\$OMARCHY_INSTALL/user/mise.sh"' "$ROOT/install/user/all.sh" ||
  fail "both mise leaves are gated"
pass "the mise leaves are gated on mise being installed"

# Condition 4 of the port: no x86_64 artifact name left hardcoded anywhere in
# the install tree. Node names its tarballs x64 or arm64.
! grep -rn 'linux-x64' "$ROOT/install" ||
  fail "no x86_64 artifact name is hardcoded in the install tree"
grep -q 'aarch64) NODE_ARCH=arm64' "$ROOT/install/user/mise-work.sh" ||
  fail "the Node tarball is looked up by the machine architecture"
pass "no x86_64 artifact name is hardcoded in the install tree"

# "Only in the AUR" says nothing about whether a package matters. These three
# are load-bearing: without xdg-terminal-exec no terminal opens even though
# foot is installed, without mise the AI CLIs are never installed, and the
# firewall leaf uses ufw-docker during system setup.
for pkg in xdg-terminal-exec mise-bin ufw-docker; do
  grep -qxF "$pkg" "$ROOT/install/arm/packages.aur-required" ||
    fail "$pkg is treated as needed, not optional" "$(cat "$ROOT/install/arm/packages.aur-required")"
  grep -qxF "$pkg" "$ROOT/install/arm/packages.aur" &&
    fail "$pkg is not also in the optional list"
done
pass "the AUR packages the desktop needs are separated from the optional ones"

# herdr is the expensive one -- it pulls zig0.15, which rebuilds Zig against
# LLVM 20 -- and must never end up in the set installed by default.
grep -qxF herdr "$ROOT/install/arm/packages.aur-required" &&
  fail "the package that pulls a compiler toolchain stays optional"
pass "the package that pulls a compiler toolchain stays optional"

# ufw-docker is used during system setup and mise during user setup, so the
# needed set has to be installed before both, not with the optional set last.
required_line=$(grep -n "Needed AUR packages installed" "$ROOT/install.sh" | cut -d: -f1)
system_line=$(grep -n 'step "System setup"' "$ROOT/install.sh" | cut -d: -f1)
optional_line=$(grep -n 'step "AUR packages"' "$ROOT/install.sh" | cut -d: -f1)
[[ -n $required_line && -n $system_line && -n $optional_line ]] || fail "install.sh has all three phases"
(( required_line < system_line )) ||
  fail "the needed AUR packages are installed before system setup" "needed:$required_line system:$system_line"
(( optional_line > system_line )) ||
  fail "the optional AUR packages still come last" "optional:$optional_line system:$system_line"
pass "the needed AUR packages land before the setup phases that use them"

# Re-running the installer used to leave a copy of every file it had itself
# written next to the original, including in /usr/share/icons and
# /usr/local/share/wayland-sessions, which are scanned by name.
grep -q 'cmp -s "\$src" "\$dest"' "$ROOT/install/arm/settings.sh" ||
  fail "a backup is only made when the file actually differs"
# scalable/ is for SVG; a PNG there is an icon lookup that returns nothing.
grep -q 'icons/hicolor/256x256/apps' "$ROOT/install/arm/settings.sh" ||
  fail "PNG icons go in a pixel-size directory, not scalable"
pass "the installer leaves no stray backups and files icons by size"

# The Hyprland profile has to load after Omarchy's own look'n'feel or it would
# be overwritten by it, and before the user's, or it would overwrite theirs.
omarchy_lua="$ROOT/default/hypr/omarchy.lua"
looknfeel_line=$(grep -n 'require("default.hypr.looknfeel")' "$omarchy_lua" | cut -d: -f1)
platform_line=$(grep -n 'require("default.hypr.platform")' "$omarchy_lua" | cut -d: -f1)
[[ -n $looknfeel_line && -n $platform_line ]] || fail "both modules are required from omarchy.lua"
(( platform_line > looknfeel_line )) ||
  fail "the platform profile loads after Omarchy's look'n'feel" "looknfeel:$looknfeel_line platform:$platform_line"
pass "the platform profile loads after Omarchy's look'n'feel"

[[ -f $ROOT/default/hypr/platform/raspberry-pi.lua ]] || fail "the Pi profile exists"
grep -q 'enabled = false' "$ROOT/default/hypr/platform/raspberry-pi.lua" ||
  fail "the Pi profile turns animations off"
pass "the Pi profile exists and turns animations off"

# Manifests are only useful if every entry is a real base package.
base=$(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$ROOT/install/omarchy-base.packages")
for manifest in packages.aur packages.aur-required packages.unavailable packages.exclude; do
  while read -r pkg _; do
    [[ -n $pkg ]] || continue
    grep -qxF "$pkg" <<<"$base" ||
      fail "$manifest only names packages that are actually in the base list" "$pkg is not"
  done < <(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$ROOT/install/arm/$manifest")
done
pass "the ARM manifests only name packages that are in the base list"

while read -r from to; do
  [[ -n ${from:-} ]] || continue
  grep -qxF "$from" <<<"$base" ||
    fail "packages.replace substitutes a package that is in the base list" "$from is not"
  [[ -n ${to:-} ]] || fail "packages.replace gives a replacement for $from"
done < <(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$ROOT/install/arm/packages.replace")
pass "every substitution names a base package and a replacement"

# The boot chain is the one place where being wrong is unrecoverable from
# inside the session. omarchy-refresh-limine is reachable from
# omarchy-reinstall-configs, which runs under set -e, so an unguarded failure
# there also abandons everything after it.
grep -q 'uname -m) == aarch64' "$ROOT/bin/omarchy-refresh-limine" ||
  fail "omarchy-refresh-limine refuses to touch the boot chain on aarch64"
pass "omarchy-refresh-limine refuses to touch the boot chain on aarch64"

guard_line=$(grep -n 'uname -m) == aarch64' "$ROOT/bin/omarchy-refresh-limine" | head -1 | cut -d: -f1)
first_mutation=$(grep -n 'sudo ' "$ROOT/bin/omarchy-refresh-limine" | head -1 | cut -d: -f1)
(( guard_line < first_mutation )) ||
  fail "the guard comes before anything is moved or written" "guard:$guard_line first sudo:$first_mutation"
pass "the guard comes before anything is moved or written"

# The shipped skills are how an agent learns this machine. A guide that
# promises behaviour the port does not have is a wrong answer waiting to be
# given confidently.
skills="$ROOT/default/agents/skills/omarchy"

grep -q '\[`arm.md`\](arm.md)' "$skills/SKILL.md" ||
  fail "the ARM guide is listed among the topic guides"
pass "the ARM guide is listed among the topic guides"

for guide in plugins.md capture.md contributing.md; do
  grep -q 'arm.md' "$skills/$guide" ||
    fail "$guide points at the ARM guide where its promises differ" "$guide does not"
done
pass "the guides whose promises differ on ARM point at the ARM guide"

# Both measured lists have to be reachable from the skill, or an agent sends
# the user to a file that only covers half the question.
grep -q 'apps.unavailable' "$skills/arm.md" && grep -q 'packages.unavailable' "$skills/arm.md" ||
  fail "the ARM guide names both measured lists"
pass "the ARM guide names both measured lists"

while read -r link; do
  [[ -f $skills/$link ]] || fail "every topic guide the skill links to exists" "$link"
done < <(grep -ohE '\]\([a-z-]+\.md\)' "$skills"/*.md | tr -d '](' | tr -d ')' | sort -u)
pass "every topic guide link resolves"

# packages.extra makes an ISO-only package reachable on a running install. It
# must stay a subset of the list the ISO builder uses, or it becomes a second
# place where dependencies are invented.
other=$(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$ROOT/install/omarchy-other.packages" | awk '{print $1}')
while read -r pkg reason; do
  [[ -z $pkg || $pkg == \#* ]] && continue
  grep -qxF "$pkg" <<<"$other" ||
    fail "packages.extra only names packages the ISO already installs" "$pkg is not in omarchy-other.packages"
  [[ -n $reason ]] || fail "every extra package states why it is needed" "$pkg"
done < <(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$ROOT/install/arm/packages.extra")
pass "packages.extra names only ISO packages, each with a reason"

# Upstream migration 1785013000 moves zram tuning out of /etc and into the
# vendor drop-in. A leaf that writes the file back takes precedence over the
# shipped tuning and drops its swap priority.
grep -q 'zram-generator.conf$' "$ROOT/install/hardware/arm/raspberry-pi.sh" &&
  fail "no install leaf writes /etc/systemd/zram-generator.conf"
pass "no install leaf writes back the zram file upstream migrated away from"

# ufw exits 1 while it is armed but not yet active, which is the only state
# the SSH guard ever runs in. Taking that at face value aborted a real install
# on a Raspberry Pi 5 after every package was in: the rule had been written,
# the exit code said otherwise, and `set -e` did the rest.
ufw_stub_dir=$(mktemp -d)
trap 'rm -rf "$ufw_stub_dir"' EXIT
mkdir -p "$ufw_stub_dir/bin"
cat >"$ufw_stub_dir/bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
cat >"$ufw_stub_dir/bin/ufw" <<'STUB'
#!/bin/bash
case "$1" in
allow)
  # The rule lands; the status check that follows it is what fails.
  echo "$*" >>"$UFW_STUB_ADDED"
  echo "ERROR: problem running" >&2
  exit 1
  ;;
show)
  [[ -f $UFW_STUB_ADDED ]] && sed 's/^/ufw /' "$UFW_STUB_ADDED"
  exit 0
  ;;
esac
STUB
chmod +x "$ufw_stub_dir/bin/sudo" "$ufw_stub_dir/bin/ufw"
printf 'ENABLED=yes\n' >"$ufw_stub_dir/ufw.conf"

source "$ROOT/install/arm/firewall-ssh.sh"

status=0
out=$(
  PATH="$ufw_stub_dir/bin:$PATH" \
  UFW_STUB_ADDED="$ufw_stub_dir/added" \
  OMARCHY_ARM_UFW_CONF="$ufw_stub_dir/ufw.conf" \
  SSH_CONNECTION="10.0.0.1 22 10.0.0.2 22" \
    omarchy_arm_keep_ssh_reachable 2>&1
) || status=$?
((status == 0)) ||
  fail "a rule that landed is not treated as a failed install" "exit $status: $out"
grep -q 'allow 22/tcp' "$ufw_stub_dir/added" ||
  fail "the SSH guard opened the port" "$(cat "$ufw_stub_dir/added" 2>/dev/null)"
pass "ufw's exit code does not abort an install whose rule landed"

# The other half: if the rule genuinely did not land, aborting is still the
# wrong answer. The firewall was armed by an earlier step, so stopping here
# leaves the machine both half-configured and unreachable after the reboot.
rm -f "$ufw_stub_dir/added"
cat >"$ufw_stub_dir/bin/ufw" <<'STUB'
#!/bin/bash
case "$1" in
allow) echo "ERROR: problem running" >&2; exit 1 ;;
show) exit 0 ;;
esac
STUB
chmod +x "$ufw_stub_dir/bin/ufw"

status=0
out=$(
  PATH="$ufw_stub_dir/bin:$PATH" \
  UFW_STUB_ADDED="$ufw_stub_dir/added" \
  OMARCHY_ARM_UFW_CONF="$ufw_stub_dir/ufw.conf" \
  SSH_CONNECTION="10.0.0.1 22 10.0.0.2 22" \
    omarchy_arm_keep_ssh_reachable 2>&1
) || status=$?
((status == 0)) ||
  fail "a firewall that cannot be opened warns instead of aborting" "exit $status"
grep -q "sudo ufw allow 22/tcp" <<<"$out" ||
  fail "the warning says exactly how to get back in" "$out"
pass "an unopenable firewall warns loudly and lets the install finish"
