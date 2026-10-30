# The ARM64 port

This fork installs Omarchy on 64-bit ARM: an Apple Silicon Mac, a Raspberry Pi
5, or an aarch64 virtual machine. Upstream Omarchy is x86_64 only, and not by
accident: its installation model, its package repositories and a third of its
hardware setup tree are all built around that assumption.

This document records what those assumptions are, which of them were adapted,
which were left alone, and what still does not work.

## Why Arch Linux ARM, and not Fedora Asahi

Fedora Asahi Remix is the best-supported distribution on Apple Silicon, so it
is the obvious target for a Mac. It was not chosen, for one reason: Omarchy is
not a desktop environment that happens to run on Arch. Its 433 commands in
`bin/` call `pacman` and `yay` directly, its update pipeline is built on
pacman hooks and AUR rebuilds, and its own software is distributed as pacman
packages. Moving that to `dnf` is not a port, it is a rewrite of the layer
that makes Omarchy Omarchy.

Keeping pacman means one distribution across both targets:

| Machine | Distribution |
|---|---|
| Apple Silicon Mac | Arch Linux ARM (the Asahi community port) |
| Raspberry Pi 5 | Arch Linux ARM |
| aarch64 VM | Arch Linux ARM |

The cost is that the Mac runs a community port rather than the officially
supported Fedora Asahi Remix. The benefit is that everything above the package
layer -- every command, every hook, the whole update pipeline -- keeps working
without being touched.

## What the repository looks like from a porting point of view

Two layers, and only one of them needed work.

**Architecture-agnostic (untouched).** The Hyprland Lua configuration under
`config/hypr/` and `default/hypr/`, the Quickshell desktop under `shell/`, the
themes, the agent skills under `default/agents/skills/`, and the great
majority of `bin/`. None of it contains an architecture assumption. Note that
upstream has moved on from what older Omarchy documentation describes: there
is no `hyprland.conf` any more (the configuration is Lua), no Waybar (the bar
is Quickshell) and no Rofi (the launcher is Omarchy's own menu).

**System and packaging (adapted).** 87 files mention `pacman`, `yay` or
`makepkg`, but almost all of them go through the same five helpers --
`omarchy-pkg-add`, `-drop`, `-present`, `-missing`, `-aur-add` -- which stayed
exactly as they are, because pacman stayed. What actually needed adapting was
narrower than the file count suggests:

- the absence of an installer at all
- the x86-only leaves under `install/hardware/`
- `/etc/pacman.conf`, which upstream replaces wholesale
- the packages that have no aarch64 build

## There is no `install.sh` upstream

Upstream Omarchy 4 is installed from an ISO. `archinstall` partitions the
disk, pacstraps `install/omarchy-base.packages`, and the target-side setup
commands (`omarchy-apply-system`, `omarchy-apply-hardware`,
`omarchy-provision-user`) run in the chroot. There is no script that installs
Omarchy onto a system that is already running.

That ISO cannot be rebuilt for aarch64 without also solving everything below,
so this fork adds `install.sh` at the repository root instead. It installs
onto a running Arch Linux ARM system, and it drives the same target-side
commands the ISO drives, in the same order:

```
preflight            architecture, distribution, platform
package plan         resolve the base list against the live repositories
deploy               copy the checkout to /usr/share/omarchy, write /etc/omarchy.conf
settings             install what the omarchy-settings package would own
system setup         omarchy-apply-system --install-user $USER --first-install
user setup           omarchy-provision-user --first-install
```

`--dry-run` prints every one of those steps and changes nothing. Every
mutating command in the script goes through a single `run()` wrapper, so there
is no second code path for the dry run to drift away from.

## The packaging problem, measured

Omarchy's own packages come from `[omarchy]` at `pkgs.omarchy.org/stable/$arch`,
and its Arch mirror is pinned to `stable-mirror.omarchy.org`. Neither has an
aarch64 tree:

```
https://pkgs.omarchy.org/stable/x86_64/omarchy.db        200
https://pkgs.omarchy.org/stable/aarch64/omarchy.db       404
https://stable-mirror.omarchy.org/core/os/aarch64/core.db 404
http://mirror.archlinuxarm.org/aarch64/core/core.db      302
```

So `install/post-install/pacman.sh`, which on x86 copies Omarchy's
`pacman.conf` and mirrorlist over the machine's own, is the single most
destructive step in the tree for an ARM install: it would leave the machine
unable to resolve a single package. On aarch64 it is replaced by
`install/arm/pacman.sh`, which edits pacman's cosmetic and behavioural options
in place, never writes a `Server` line, and strips `[multilib]` and
`[omarchy]` if they are present.

Resolving `install/omarchy-base.packages` (148 packages) against the live
Arch Linux ARM aarch64 databases gives:

| | Count |
|---|---|
| In `core`/`extra`/`alarm` for aarch64 | 123 |
| Available in the AUR, compiled on the machine | 11 |
| No aarch64 source at all | 13 |
| Bootstrapped from source by `install.sh` | 1 (`yay`) |
| **Total** | **148** |

Two of the 123 arrive under a different name: `nvim` becomes `neovim` and
`ttf-jetbrains-mono-nerd-basic` becomes `ttf-jetbrains-mono-nerd`, replacing
Omarchy's own builds with their upstream equivalents.

Those four categories are manifests under `install/arm/`, not logic inside
`install.sh`: `packages.aur`, `packages.replace`, `packages.unavailable`,
`packages.exclude`. A base package that appears in none of them is reported as
unaccounted for rather than silently dropped, and the test suite fails if the
manifests and the base list drift apart.

### Installing apps afterwards

The measured table above is about the base install. Apps installed later hit
the same wall from the other side: on x86_64 most of what the Install menu
offers comes from `[omarchy]`, and that repository is not in `pacman.conf`
here, so `pacman` answers `target not found` for a Spotify that will never be
built for ARM and for a VS Code that the AUR builds for aarch64 perfectly
well. The two cases deserve different answers.

`omarchy-pkg-add` now resolves a name before handing it to pacman, on aarch64
only:

- in the repositories, under this name or the one in `packages.replace`:
  install it, unchanged from x86 behaviour
- on the measured x86-only list (`install/arm/apps.unavailable`): refuse, and
  print the reason
- in the AUR with `aarch64` or `any` in its `arch=()`: say so and offer to
  build it. Interactively that is a prompt; from a script it is a printed
  `omarchy pkg aur add` command. Never a silent build: one AUR package pulled
  a toolchain that filled this VM's disk once already
- AUR unreachable: treat it as buildable and let `yay` report the network
  failure. A timeout is not evidence about an architecture

`apps.unavailable` was measured the same way as the base table: repository
databases first, then the `arch=()` line of each AUR PKGBUILD, fetched through
the package base so split packages resolve. Of twenty-five menu packages
checked, nine build for aarch64 from the AUR and would have been unreachable
without this: VS Code, Ghostty, Zen, Brave, sunshine, 1Password CLI, NordVPN,
`once`, and the Codex desktop app.

One name is not a verdict but a rename: Arch Linux ARM has no generic
`linux-headers`, only headers named after the installed kernel
(`linux-aarch64-headers`, or `linux-rpi-headers` on the Pi). That is resolved
from the running system rather than pinned in a file, because the two targets
disagree.

### The AUR is not a free substitute on ARM

On x86_64 an AUR package with a `-bin` suffix is a download. On aarch64 there
are no prebuilt binaries, so every one of the 11 is compiled on the machine,
and the dependency chain is not shallow: `herdr` pulls `zig0.15`, which
rebuilds Zig against LLVM 20. On the first real install that filled a 15 GB
disk and was still compiling long after the desktop itself was ready.

So the AUR step is last, after the desktop is provisioned, and off unless
`--with-aur` is passed. A machine that runs out of space or patience there
still ends up with a working Omarchy, and the cost is an optional app. On a
Raspberry Pi booting from an SD card, that default is not a nicety.

### What is lost

The 13 packages with no aarch64 build, and why:

- `omacalc`, `omacut`, `omawrite`, `omarchy-nvim`, `ttfx`, `tobi-try`,
  `hyprland-preview-share-picker` -- Omarchy's own software, published only
  through the x86_64 repository above. Building them for aarch64 means
  building them from their upstream sources, which is the largest remaining
  piece of work on this fork.
- `obs-studio`, `pinta`, `dotnet-runtime` -- Arch builds them for x86_64 only.
- `obsidian` -- proprietary Electron application with no aarch64 Arch package.
- `asdcontrol`, `qemu-user-static-binfmt` -- x86-only packaging.

None of them is needed for the desktop to come up. Hyprland, Quickshell, SDDM,
uwsm, foot, Chromium and the whole theming stack are all in Arch Linux ARM's
aarch64 `extra`.

## Hardware setup

`install/hardware/all.sh` wires 39 leaves. On ARM, 29 of them install a
driver, firmware or kernel that has no aarch64 build; 7 are hardware-neutral
and run everywhere; 3 are new and ARM-only. They are gated with
`run_logged_x86` rather than deleted, which keeps this fork rebasable on
upstream and keeps a machine's install log accounting for every step upstream
would have run.

Four ARM leaves were added, each self-gating on the detected platform the way
upstream's leaves self-gate on PCI IDs and DMI strings:

- `install/hardware/arm/vulkan.sh` -- `vulkan-asahi` on a Mac,
  `vulkan-broadcom` on a Pi, `vulkan-virtio` plus the software rasterizer in a
  VM. The x86 leaf matches GPU vendors on the PCI bus, and neither the Apple
  Silicon GPU nor the Pi's VideoCore VII is a PCI device.
- `install/hardware/arm/apple-silicon.sh` -- `speakersafetyd`, which enforces
  the thermal limits of the internal speakers. Asahi ships it because the
  hardware has no protection of its own.
- `install/hardware/arm/raspberry-pi.sh` -- zram, because the Pi tops out at
  8 GB with no swap by default.
- `install/hardware/arm/pinebook-pro.sh` -- a systemd sleep drop-in that
  selects s2idle, because a deep resume on the Pinebook Pro hangs often enough
  to cost a hard power-off.

One leaf outside `install/hardware/` needed the same treatment:
`install/config/snapper.sh`. Snapper is wired to limine on x86 -- the same
step enables `limine-snapper-sync.service` -- and snapper is not in the ARM
package set at all. Left ungated it would abort the first ARM install
outright, because the leaf runs under `set -e` and `snapper create-config`
fails when the command does not exist.

Note that `install/hardware/apple/` is **not** about Apple Silicon. Those are
T2 quirks for Intel Macs, which are x86_64 machines, and they are gated off on
ARM.

### Platform detection

Five commands, reading the flattened device tree at `/proc/device-tree`,
and on ACPI-only aarch64 machines the platform devices the firmware names:

```bash
omarchy hw platform            # apple-silicon | raspberry-pi-5 | raspberry-pi | cix-sky1 | pinebook-pro | generic-aarch64 | x86_64
omarchy hw aarch64
omarchy hw apple silicon
omarchy hw raspberry pi [--5]
omarchy hw cix sky1
omarchy hw pinebook pro
```

They cost nothing to call, work before any package is installed, and are what
the install leaves, the Hyprland profile and the agent skill all branch on.

## The boot chain is deliberately untouched

On x86 Omarchy owns the bootloader: limine, `/etc/limine-entry-tool.d/`
drop-ins, mkinitcpio hooks, snapper integration. A Raspberry Pi boots through
its own firmware and `linux-rpi`; an Apple Silicon Mac boots through m1n1 and
U-Boot. This fork installs none of it, and `install/arm/settings.sh` skips
those drop-ins explicitly and says so as it goes.

This is the one place where being conservative is not a style preference: a
wrong initramfs hook on either machine produces a device that no longer boots
and cannot be recovered from inside the session.

## The agent layer

Omarchy ships an agent skill at `default/agents/skills/omarchy/` that lets an
AI CLI edit the desktop configuration in natural language. It needed no
porting: it already targets `~/.config/`, and its hot-reload contract
(`hyprctl reload` followed by `hyprctl configerrors`) is architecture-neutral.

What was added is `arm.md`, one more topic guide covering what an agent
working on an ARM machine needs to know that it cannot infer: how to identify
the board, that some stock packages are absent by design and where the list
is, that `[omarchy]` and `[multilib]` must never be added to `pacman.conf`,
and that the boot chain is out of scope.

## Raspberry Pi tuning

`default/hypr/platform/raspberry-pi.lua` loads after Omarchy's own
look'n'feel and before the user's. It turns animations off and pins blur,
shadows and rounding off. The Pi 5's VideoCore VII renders a tiling desktop
perfectly well but shares memory bandwidth with the CPU, and full-screen
per-frame passes are what make it feel like it is catching up.

It is a default, not a lock: `~/.config/hypr/looknfeel.lua` loads afterwards
and wins.

## Testing

```bash
./install.sh --dry-run            # on the target machine
./install.sh                      # the real thing
./install.sh --with-aur --skip-packages   # add the AUR extras later
bash test/shell                   # the full suite, on any Linux box
```

Seven test files cover this fork specifically, 106 assertions in all:

- `test/shell.d/arm64-platform-test.sh` -- device-tree detection against
  fixtures for a Pi 5, an older Pi, two generations of Mac, and a VM;
  including that an Intel T2 Mac never matches the Apple Silicon predicate.
- `test/shell.d/arm64-install-test.sh` -- drives `install.sh --dry-run` in a
  stubbed sandbox and asserts that it reaches neither `sudo` nor a mutating
  `pacman`, that it refuses x86_64 and non-Arch distributions, and that the
  boot-chain drop-ins are skipped.
- `test/shell.d/arm64-gating-test.sh` -- asserts every x86-only hardware leaf
  is still gated, the pacman.conf restore cannot run on ARM, and the manifests
  have not drifted from the base package list.
- `test/shell.d/arm64-keyboard-test.sh` -- layout detection from
  `/etc/vconsole.conf`, the X11 keymap and the console `KEYMAP`, including the
  aliases that are not xkb layout names and the names that only look like one.
- `test/shell.d/arm64-sudo-keepalive-test.sh` -- the sudo timestamp is primed
  once before the first escalation, refreshed for the length of the run, and
  stopped afterwards; a dry run authenticates nothing.
- `test/shell.d/arm64-packages-test.sh` -- runs `omarchy-pkg-add` against a
  stubbed pacman: an x86-only app is refused with its reason before pacman is
  involved and without reaching the network, an AUR-buildable one is offered
  rather than compiled, an unreachable AUR does not become a verdict, and a
  plain repository package installs exactly as it did before.
- `test/shell.d/arm64-screensaver-test.sh` -- runs the launcher with `ttfx`
  absent and asserts no window is spawned, the idle path stays silent, the
  menu path explains itself, and a machine that has `ttfx` is unaffected.
- `test/shell.d/arm64-seed-home-test.sh` -- the first pass replaces and backs
  up, a later pass fills in what is missing and leaves the user's own edits
  alone, and a home seeded before the marker existed is still recognised.

## What the first real install found

Everything above the packaging layer was covered by tests before any of it
ran. The tests found nothing. The machine found all of the following, in the
order they surfaced, and every one of them was fatal to the install, to the
session, to an app someone tried to install afterwards, or to the next update:

| | |
|---|---|
| The Arch Linux ARM keyring is not installed by a pacstrap from archboot | 200-odd `unknown trust` errors, no package installable, and the fix is signed by the untrusted key |
| `herdr` pulls `zig0.15`, which rebuilds Zig against LLVM 20 | filled a 15 GB disk with the desktop still not deployed |
| `ufw-docker` is AUR-only | `omarchy-apply-system` aborted on a Docker convenience rule |
| `mise` is AUR-only | `omarchy-provision-user` aborted with `mise: command not found` |
| The `omarchy` package puts `bin/*` on PATH, and has no aarch64 build | session came up as a bare compositor: no bar, no menu, no keybinding |
| `/etc/skel` only fires at user creation | the user ran on Hyprland's autogenerated config, missing 136 shipped files, and nothing logged an error |
| `misc.vfr` is not a Hyprland 0.56.1 config key | the Pi profile applied but left a config error behind |
| Nobody asks for a keyboard layout on a running machine | the desktop came up in US on a French keyboard, and the first thing it broke was the lock screen password |
| `xdg-terminal-exec` and `mise` are AUR-only on aarch64 | no terminal opened at all, and the whole AI CLI layer was silently absent |
| `--first-install` makes `omarchy-provision-user` claim to be the ISO chroot | user setup failed looking for tarballs under `/opt/packages` |
| Migration markers written without their `.sh` extension | all 84 shipped migrations would have replayed on first login |
| `omarchy-screensaver` respawns `ttfx` in a loop | with `ttfx` absent the loop spins a core and floods the terminal with `command not found`, and the window it opens and closes reads to the idle service as a dismissal, cancelling the pending lock |
| SDDM has no last user on a machine the ISO never installed | the greeter asks only for a password and logs in as `""`; every password fails with `User not known to the underlying authentication module`, which reads like a typo. The ISO seeds `/var/lib/sddm/state.conf`; `install/arm/login.sh` now does the same (found on an aarch64 VM under Parallels) |
| The Install menu offers x86-only apps | `pacman` can only answer `target not found`, which reads like a broken install rather than an app that was never built for the machine |
| Rerunning the installer re-seeds `/etc/skel` over the home | all 152 shipped defaults copied over the user's home again. The per-file backup is written once, so anything edited after the first install was destroyed with nothing left to recover it |
| Deploy emptied `$OMARCHY_PATH` before refilling it | for the length of a 1600-file copy, Hyprland's `bootstrap.lua` and all 439 commands in `/usr/bin` pointed at nothing |
| Nothing pauses Hyprland's config auto-reload | a reload landing while the configs are being rewritten drops the session into emergency mode: no binds, no keyboard layout, and a lock screen that then refuses the password being typed |
| 19 migrations call `omarchy-pkg-add`, some for packages with no ARM build | `omarchy-migrate` runs under `set -e`, so one of those leaves its marker unwritten and blocks every migration behind it, on every login, forever |
| `omarchy-refresh-limine` is reachable from `omarchy-reinstall-configs` | under `set -e`: it moved a `limine.conf` that does not exist, copied one in beside the Pi's firmware, then called a `limine-update` that is not installed, abandoning the rest of the reset |
| Omarchy ships zram tuning, the ISO ships the generator | the drop-in was installed and `zram-generator` was not, so the machine had no compressed swap at all |
| PipeWire comes in as a dependency, its PulseAudio server does not | `pactl` answered "Connection refused" on a finished desktop: three shipped `omarchy-audio-*` commands talking to nothing, and silence in every application that speaks the PulseAudio API |
| Two commands are `644` in git | the omarchy package installs `bin/*` with `install -Dm755`, so they work on x86. Linking only what git marks executable left two menu entries doing nothing |

The keyboard one deserves its own note, because the mechanism was already
there and still failed. `default/hypr/input.lua` reads `XKBLAYOUT` out of
`/etc/vconsole.conf` and falls back to `us`. On an ISO install that is enough:
the installer asked for a layout and wrote it. Installing onto a running
machine, nobody asks, and a command-line Arch Linux ARM install typically has
`KEYMAP` set and `XKBLAYOUT` absent. So `install/arm/keyboard.sh` finds what
the system already declares -- `XKBLAYOUT`, then the X11 keymap `localectl`
writes, then the console `KEYMAP` reduced to its xkb layout -- and records it
where Omarchy looks. Upstream's Lua is untouched. An unrecognised keymap is
left alone rather than guessed at: a layout Hyprland rejects leaves a desktop
with no working keyboard at all. Recognising one means asking
xkeyboard-config's own `base.lst` whether the name is a layout, not deciding
from its shape -- `en` is two letters, is no layout, and fails to compile into
a keymap only once the lock screen is already refusing a correct password.

The bare-compositor pair are the instructive ones. Both produced a broken desktop with a
completely clean log, because nothing had failed: a compositor with no
commands on its PATH starts perfectly, and a user with no shipped config gets
Hyprland's own default and runs it happily.

The ordering trap is worth stating on its own. The ISO seeds `/etc/skel` and
*then* creates the user. Installing onto a running machine inverts that, and
`/etc/skel` reaches nobody. Anything that relies on user creation to deliver a
file has the same problem here.

## What the Raspberry Pi 5 added

The VM proved the software. The board proved the substrate.

Getting Arch Linux ARM onto a Pi 5 is undocumented by the distribution itself:
archlinuxarm.org has no Raspberry Pi 5 platform page, the newest one is the Pi
4. The image it does ship, `ArchLinuxARM-rpi-aarch64-latest.tar.gz`, carries
the Pi 5 device trees but boots through U-Boot 2025.01 running the *generic*
`linux-aarch64` kernel, not `linux-rpi`. Whether that U-Boot initialises a
bcm2712 was not worth discovering on a board with no screen attached, so the
card was rebuilt on the downstream chain instead: the firmware loads
`kernel8.img` directly with `initramfs followkernel`, `linux-rpi` 6.18.45,
`raspberrypi-overlays`, and `dtoverlay=vc4-kms-v3d-pi5` under a `[pi5]`
section. That is the chain Raspberry Pi OS uses. It came up first try, and
`root=PARTUUID=` keeps it indifferent to how the card is enumerated.

| | |
|---|---|
| `ufw` exits 1 with a bare `ERROR: problem running` when it is armed for the next boot but not yet active | adding a rule ends in a status check that runs `iptables -L ufw-user-input`, and that chain exists only once ufw has started. The rule lands anyway. Under `set -e` this stopped the install after every package was in and before the user was provisioned, which is worse than what the step defends against. Fixed by judging the step on whether the rule landed |
| A test can assert the wrong branch | `--with-aur bootstraps an AUR helper first` held only where no helper is on PATH. On a machine this fork has already installed, `yay` exists, `bootstrap_aur_helper` correctly returns early, and a working installer failed its own test |
| `sudo` is not in the Arch Linux ARM base image | the installer needs it from its first privileged step |
| A hostname change moves the DHCP lease | the Pi answered on a different address after the rename, then took its old one back at the next boot. Nothing was broken; five minutes were spent proving it |

What the board confirmed rather than found:

- `omarchy-hw-platform` answers `raspberry-pi-5` on the real device tree, not
  just on the fixture the tests feed it
- the GPU comes up on `vc4-drm` with `card0`, `card1` and `renderD128`, which
  is what a Wayland compositor needs and what no VM could demonstrate
- zram is 3.9 GB at priority 100 with `[zstd]` selected, so the compression
  this fork ships tuning for is the compression it gets
- re-running `install.sh` reported 152 shipped defaults `already current` and
  replaced none, which is the home-seeding fix behaving on hardware
- after a reboot: `systemctl --failed` empty, `ufw` active with SSH open,
  SDDM running

## What the CIX Sky1 (Minisforum MS-R1) added

The MS-R1 is a 12-core Armv9 desktop (CIX CP8180: eight Cortex-A720, four
A520, a Mali-G720, 32 GB) sold with the vendor's Debian 12. Its firmware is
UEFI with ACPI only -- there is no `/proc/device-tree` -- and the only kernel
with working NIC, NVMe, USB, display and GPU today is the vendor's
6.6.10-cix. So the Arch root runs on that kernel: the vendor `Image` and
initramfs boot from the ESP through a separate EFI entry with
`root=PARTUUID=` pointing at the Arch partition, and the vendor's
`/lib/modules/6.6.10-cix-build-generic` and firmware are copied in.
Everything below is that kernel meeting stock Arch and Omarchy.

| | |
|---|---|
| Platform detection saw `generic-aarch64` | with no device tree the board never reached a case. The Sky1 is now matched by the `cix,sky1` compatible when booted with a device tree, and on ACPI by its display engines (`CIXH5010:*` under `/sys/bus/platform/devices`) |
| `pacman -Syu` failed in its sandbox | "restricting filesystem access failed because Landlock is not supported by the kernel". The vendor kernel has no Landlock LSM. `install/arm/kernel-capabilities.sh` turns on `DisableSandboxFilesystem` and `DisableSandboxSyscalls` when `landlock` is missing from `/sys/kernel/security/lsm`, before the keyring step's first pacman call |
| ufw could not load a rule | `iptables v1.8.13 (nf_tables): Could not fetch rule set generation id`. The kernel has `CONFIG_IP_NF_IPTABLES=y` but no nf_tables, and Arch's `iptables` is the nft backend. The capabilities step swaps in `iptables-legacy` when the kernel config says so, and sets `IPV6=no` for ufw when IPv6 iptables is missing too |
| Boot waited 90 s, twice | `Timed out waiting for device /dev/zram0`: no zram in the kernel (`CONFIG_ZRAM` is not set). The step writes an `/etc/systemd/zram-generator.conf.d/90-omarchy.conf` override with no device when the config says zram is absent. Userspace startup went from 3 min 2 s to 3.8 s |
| Hyprland aborted before its first frame, SDDM's greeter included | `MESA-EGL: warning: egl: failed to create dri2 screen` on every card, then SIGABRT. The displays are `linlondp` KMS devices (one DRM card per output) and the GPU is the proprietary `mali_kbase`; Mesa drives neither. `install/hardware/arm/cix-sky1.sh` puts `LIBGL_ALWAYS_SOFTWARE=1` in `/etc/environment` (pam_env reaches the greeter and the session) unless `panthor` is loaded, and `vulkan.sh` installs `vulkan-swrast` |
| `setcap` fails | the vendor kernel's ext4 has no security xattrs, so `newuidmap`, `gst-ptp-helper`, `gsr-kms-server` and `gvfsd-nfs` install without capabilities. Not fixed here: it is the kernel's to fix |

What the board confirmed:

- `omarchy-hw-platform` answers `cix-sky1` on the real ACPI tables
- Hyprland, Quickshell and the SDDM greeter run on llvmpipe at 3840x2160
  (the DP output runs at 30 Hz at 4K); the desktop idles at a load under 2
- after a reboot: userspace in under 4 s, `systemctl --failed` empty, ufw
  active with SSH open, SDDM running
- 20 minutes of `stress-ng` on all 12 cores with 60% of RAM in use left no
  kernel errors

The open path to a GPU-accelerated desktop is a newer kernel: the Sky1-Linux
community kernels (6.18 LTS, 7.0) carry `panthor` and the display drivers,
and Mesa then drives the Mali-G720 itself. Nothing in this fork needs to
change for that; the software-rendering switch steps aside when `panthor` is
loaded.

## What the Pinebook Pro added

A Pine64 Pinebook Pro (RK3399, Mali-T860 on `panfrost`, 4 GB) on Arch Linux
ARM's `linux-aarch64` kernel, installed with `install.sh` and then used as a
daily laptop. It is the first machine here with a lid, a battery and a built-in
keyboard, and most of what it found was in those three.

| | |
|---|---|
| The bar and every panel render solid black while their click targets work | Qt 6.12 added a QtQuick `Color` singleton. An unversioned `import QtQuick` brings it in, and it shadows `qs.Commons`' `Color` for unqualified access whatever the import order, so every `Color.<token>` is undefined. Not ARM-specific: any machine on Qt 6.12. Fixed by pinning the shell's imports to `QtQuick 6.11` |
| Windows have no borders and no gaps | `install/arm/settings.sh` seeded the whole of `default/hypr/toggles` into `/etc/skel`, and a file in the toggle state directory means that toggle is on, so `window-no-gaps` and `single-window-aspect-ratio` were on for every user. Fixed by seeding `flags.lua` alone |
| New terminals type digits for `u i o j k l m` | the keyboard has an embedded keypad layer and Omarchy turns numlock on at login. `default/hypr/platform/pinebook-pro.lua` turns it off; the platform profile now loads after the input defaults so it can |
| Closing the lid sometimes needs a hard power-off to recover | deep suspend: the log ends at `PM: suspend entry (deep)` and the kernel never resumes. s2idle woke every time it was tried, within a couple of seconds |
| After the first unlock, the screen no longer locks before suspend | Quickshell 0.3.2 can drop `WlSessionLock.locked` to false without emitting `lockStateChanged`, which left the lock service's `locked` binding stuck at true: every later lock request was treated as redundant, and logind suspended after the 12 s wait with the session open. With the lid reopened inside that window, the machine then slept with the lid open and nothing left to wake it |
| A wrong Wi-Fi password fails silently from the network panel | `failNetworkAction()` refreshes the list and destroys the row whose handler is still running, so the reprompt check threw on `root` being undefined |
| `vulkan-virtio` and `vulkan-swrast` installed on real hardware | the board fell through to `generic-aarch64`, whose branch is meant for VMs. Midgard has no Mesa Vulkan driver, so the Pinebook Pro branch installs nothing |

What the machine confirmed rather than found:

- `omarchy-hw-platform` answers `pinebook-pro` on the real device tree
  (`pine64,pinebook-pro`, `rockchip,rk3399`)
- Hyprland 0.56 runs on `panfrost` through GLES 3.0 (it asks for 3.2 and falls
  back), and the stock look holds up with blur off
- NetworkManager on the `brcmfmac` radio, Bluetooth, audio, battery, backlight,
  SDDM and ufw all work with no board-specific setup

Installs that predate this profile can get the sleep fix without reinstalling:

```bash
sudo mkdir -p /etc/systemd/sleep.conf.d
printf '[Sleep]\nMemorySleepMode=s2idle\n' | sudo tee /etc/systemd/sleep.conf.d/50-omarchy-pinebook-pro.conf
```

## Validated on an aarch64 machine

An Arch Linux ARM aarch64 VM, installed from archboot, driven end to end:

- `./install.sh --dry-run` and then the real run, to completion
- package resolution against the live Arch Linux ARM databases matching what
  the manifests predicted exactly: 123 from the repositories, 11 AUR-only, 13
  with no aarch64 build, nothing unaccounted for
- Hyprland 0.56.1 running under Wayland, `hyprctl configerrors` clean, 228
  keybindings loaded, the Omarchy menu bound
- the Quickshell bar running: idle service, polkit agent, idle monitor
- the machine's own keyboard layout inherited: `KEYMAP=fr` alone became a
  French session, through upstream's own mechanism, with the user's
  `input.lua` left untouched
- `claude --version` answering `2.1.241 (Claude Code)`, installed by mise
  through `install/user/mise.sh` like every other Omarchy machine
- `omarchy-launch-terminal` opening foot through `xdg-terminal-exec`
- a rule added to `~/.config/hypr/bindings.lua`, applied with `hyprctl
  reload`, visible in `hyprctl binds` a second later and gone again when
  reverted -- the loop the agent skill prescribes, on ARM
- the Raspberry Pi profile proven by forcing the platform predicate: animations
  off under `raspberry-pi-5`, on again when the predicate is restored, no
  config errors either way
- both `install/hardware/arm/` leaves run for real against a Pi 5 device-tree
  fixture: `raspberry-pi.sh` writes the platform state and nothing else,
  `vulkan.sh` resolves and installs `vulkan-broadcom` from the aarch64
  repositories, and the Apple Silicon leaf correctly does nothing on the same
  machine. The board has since confirmed the fixture: see below

## What is degraded, and by how much

Everything this fork skips was audited against the rest of the tree: for each
package left out, what references it, and whether that reference is a code
path someone actually walks. Three turned out to be load-bearing rather than
optional and are now installed either way -- `xdg-terminal-exec`, `mise-bin`,
`ufw-docker`, see above. What remains:

| Missing | What it costs |
|---|---|
| `ttfx` | no screensaver. `omarchy-launch-screensaver` exits without opening a window, so idle goes straight to the lock at its own timeout; asking for it from the menu says why. The lock screen is unaffected: it only ever kills `ttfx`, it does not draw with it |
| `tensaku` | screenshots and recordings still work (`grim`, `slurp`); the post-capture editor does not open |
| `hyprland-preview-share-picker` | screen sharing uses xdph's own picker. The shipped `xdph.conf` names the missing binary, and xdph will not fall back while it does, so the installer comments the line out |
| `omarchy-nvim` | Neovim is installed and works; Omarchy's configuration for it is not there |
| `omacalc`, `omacut`, `omawrite`, `cliamp`, `herdr`, `aether` | their keybindings and menu entries do nothing. Four of them are one `--with-aur` away |
| `obsidian`, `obs-studio`, `pinta`, `localsend`, `dotnet-runtime` | applications, absent |
| `snapper` | no filesystem snapshots. It is wired to limine on x86, and neither is ported |
| `asdcontrol` | Apple Studio Display brightness. Irrelevant on both targets |
| zstd zram | the shipped tuning asks for zstd, and Arch Linux ARM's `linux-aarch64` offers only `[lzo-rle] lzo` in its zram module. Compressed swap works there at lzo-rle's ratio rather than zstd's ~3:1. This does not apply on a Pi: `linux-rpi` offers `lzo-rle lzo lz4 [zstd]`, and the shipped drop-in gets exactly what it asks for |

Nothing in that table stops the desktop coming up, and nothing in it is
silent: the installer names every skipped package at the end of a run.

## What is not done

- **Omarchy's first-party packages have no aarch64 build.** Seven packages,
  listed above. This is the largest remaining piece of work and the only one
  that costs the desktop anything visible.
- **The Apple Silicon target needs a substrate the Asahi project no longer
  ships.** The official Asahi installer's own data file offers Fedora Asahi
  Remix, a UEFI-only environment, and a tethered development mode. Arch Linux
  ARM is not among them, and Fedora is dnf, which this port cannot use. The
  remaining route is asahi-alarm.org, a community Arch Linux ARM for Apple
  Silicon with its own installer: a smaller project than Arch Linux ARM's own
  Raspberry Pi support, and a real dependency to weigh before counting the Mac
  as a target. The UEFI-only option is the other way in, at the cost of
  bringing your own kernel and Mesa.
- **The Mac has not run this.** The Pi 5 has, and the section below records
  what that changed. Nothing here proves Asahi's GPU stack, and
  `install/hardware/arm/apple-silicon.sh` has still never executed on the
  hardware it is written for.
- **No display has been attached to the Pi.** Everything below was measured
  over SSH with both HDMI outputs reading `disconnected`. The driver is
  loaded and the render node exists, which is the necessary condition, but
  nobody has seen the session come up on a screen, and the thermal behaviour
  of a real desktop under load is unmeasured.
- **The AUR path is untested end to end.** It is off by default. The three
  packages this fork treats as load-bearing do get built -- `yay` from source,
  then `mise-bin`, `ufw-docker` and `xdg-terminal-exec` -- so the machinery
  works; the eight optional ones behind `--with-aur` have never been run.
- **The ISO is not ported.** Installation is onto a running system only. An
  aarch64 ISO would need an ARM bootloader story per board, which is a
  different project.
- **`omarchy update` is untested on ARM.** It runs AUR rebuilds and pacman
  hooks; the pacman configuration it expects is not the one an ARM machine
  has.
