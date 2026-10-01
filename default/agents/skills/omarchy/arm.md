# ARM64 (aarch64)

Read this when the machine is an Apple Silicon Mac, a Raspberry Pi, or any
other aarch64 board. Everything in the other guides still applies; this one
covers only what differs.

## Which machine is this?

```bash
omarchy hw platform          # apple-silicon | raspberry-pi-5 | raspberry-pi | cix-sky1 | generic-aarch64 | x86_64
omarchy hw aarch64           # exit 0 on 64-bit ARM
omarchy hw apple silicon     # exit 0 on an M-series Mac, never on an Intel T2 Mac
omarchy hw raspberry pi      # exit 0 on any Pi; --5 restricts to the Pi 5
omarchy hw cix sky1          # exit 0 on a CIX Sky1 (Minisforum MS-R1, Radxa Orion O6)
```

These read the flattened device tree (`/proc/device-tree`), so they work
before any package is installed and cost nothing to call from a hook or a
config file.

## Hyprland

Configuration, reload and validation are identical to x86: edit the Lua files
in `~/.config/hypr/`, then

```bash
hyprctl reload
hyprctl configerrors
```

On a Raspberry Pi, Omarchy loads `default/hypr/platform/raspberry-pi.lua`
after its own defaults. It turns animations off and pins blur, shadows and
rounding off, because the VideoCore VII GPU shares memory bandwidth with the
CPU and full-screen passes are what make the desktop feel slow there.

That file is a default, not a lock. `~/.config/hypr/looknfeel.lua` loads after
it and wins:

```lua
-- Bring the animations back on a Pi
hl.config({ animations = { enabled = true } })
```

Never edit `default/hypr/platform/raspberry-pi.lua` itself: it lives under
`$OMARCHY_PATH`, which an update overwrites.

## Installing packages and apps

`omarchy pkg add` and `omarchy pkg aur add` work as they do on x86, against
Arch Linux ARM's aarch64 repositories. What differs is what those repositories
carry, and it differs in two directions.

Some base packages have no aarch64 build, so an install on this machine will
have skipped them. `install/arm/packages.unavailable` in `$OMARCHY_PATH` is
that list, with a reason per package. Before telling the user a stock Omarchy
command is broken, check whether the package behind it is on it.

Applications are the bigger difference. On x86_64 most of what the Install
menu offers comes from the `[omarchy]` repository, which has no aarch64 tree
and is therefore not in `pacman.conf` here. Some of those packages exist in
the AUR and build for aarch64; others are x86 binaries that never will.
`install/arm/apps.unavailable` records the measured verdict for the ones that
never will, again with a reason.

`omarchy pkg add` reads both lists, so it answers instead of failing blankly:

```bash
omarchy pkg add spotify        # refused: proprietary, the AUR builds x86_64 only
omarchy pkg add ghostty        # offers to build it from the AUR for aarch64
omarchy pkg add chromium       # installs from the repositories, as on x86
```

Ask before starting an AUR build rather than after: it compiles on the
machine, and on a Raspberry Pi one package can take tens of minutes and pull a
whole toolchain onto a small disk.

`omarchy pkg add` exits 90 when everything installable was installed and the
rest was left out for the architecture. It is not a failure to debug:
`omarchy-migrate` treats it as a skip so one migration asking for an x86-only
package cannot block every migration behind it. Any other non-zero exit is a
real failure.

### When an app has no ARM package

Work down this order, and stop at the first that holds:

1. The Arch Linux ARM repositories, under the app's own name.
2. A container image that publishes `linux/arm64`. Check before suggesting it:
   `docker manifest inspect <image> | grep -A2 architecture`. This is how most
   self-hosted services (n8n, Grafana, databases) run fine here, and Omarchy's
   own `omarchy install docker dbs` already works this way.
3. The AUR, if its `arch=()` line names `aarch64` or `any`.
4. Nothing. Say so plainly and name the reason; do not send the user to a
   generic Linux install script that will fetch an x86_64 binary.

Two categories are permanently out, not merely missing: anything under
`[multilib]`, which does not exist on aarch64, and the Windows compatibility
stack, since Arch Linux ARM ships no wine. Steam, Lutris with wine, Heroic and
Battle.net belong to that group. For a Windows desktop program that must run,
offer the Windows VM instead (`omarchy windows vm install`): on ARM it installs
Windows 11 on Arm under KVM, whose Prism emulator runs x64 programs. It has no
GPU acceleration, so it suits office work and light CAD, not games.

### Package names that differ

`linux-headers` does not exist on Arch Linux ARM. Headers are named after the
installed kernel, `linux-aarch64-headers` on a generic machine and
`linux-rpi-headers` on the Pi kernel. `omarchy pkg add` substitutes the right
one; write the substitution yourself if you are calling `pacman` directly.
`install/arm/packages.replace` holds the rest of the renames.

## What is degraded

Four things the other guides promise behave differently here. None of them
stops the desktop working, and none of them is worth "fixing" by pointing the
code at some other program.

**No screensaver.** It is drawn by `ttfx`, which is x86_64-only.
`omarchy-launch-screensaver` exits without opening a window rather than opening
one that dies, which would read to the idle service as the user dismissing the
screensaver and would cancel the pending lock. Idle still locks the screen on
its own timeout, so `idle.lock` works and `idle.screensaver` does nothing.

**No annotation editor after a screenshot.** `tensaku` has no aarch64 build.
Capture itself is unaffected: the file is written and copied to the clipboard,
and only the notification's edit action does nothing.

**Screen sharing uses xdph's own picker.** `hyprland-preview-share-picker` is
first-party and x86_64-only. The installer comments its line out of
`xdph.conf`, because naming a missing binary stops xdph falling back.

**Neovim has no Omarchy configuration.** Neovim itself is installed; the config
comes from `omarchy-nvim`, which is first-party and x86_64-only.

The full list, with a reason per package, is in
`$OMARCHY_PATH/install/arm/packages.unavailable` for the base install and
`apps.unavailable` for everything a user installs afterwards.

## Never add these repositories

Two of Omarchy's own pacman repositories are x86_64-only and will break
`pacman -Sy` outright if they are added to `/etc/pacman.conf` here:

- `[omarchy]` at `pkgs.omarchy.org`, which has no aarch64 tree
- `[multilib]`, which has no meaning on aarch64

If `/etc/pacman.conf` on this machine ever ends up with either, remove the
section. `install/arm/pacman.sh` is what normally keeps them out.

## The boot chain is not Omarchy's

On x86 Omarchy owns the bootloader: it installs limine, writes
`/etc/limine-entry-tool.d/` drop-ins and adds mkinitcpio hooks. None of that
runs on ARM, because a Raspberry Pi boots through its own firmware and
`linux-rpi`, and an Apple Silicon Mac boots through m1n1 and U-Boot.

So: do not run `omarchy refresh limine`, do not edit mkinitcpio hooks, and
treat any suggestion to change the boot configuration as out of scope for this
skill. Getting it wrong on either machine means a device that no longer boots
and cannot be recovered from inside the session.
