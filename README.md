# Omarchy on ARM64

> [!IMPORTANT]
> Upstream [Omarchy](https://github.com/basecamp/omarchy) now supports aarch64 natively on its `quattro` branch: Apple Silicon, Snapdragon laptops, NVIDIA N1x and GB10, and a generic `aarch64` platform for Raspberry Pis and ARM VMs. This fork is no longer actively developed and won't be maintained long-term. Please propose new ARM work, board support and fixes upstream.

A fork of [Omarchy](https://omarchy.org) that installs on 64-bit ARM instead
of x86_64: an Apple Silicon Mac, a Raspberry Pi 5, or an aarch64 virtual
machine, all running Arch Linux ARM.

```bash
git clone -b arm64 https://github.com/alexisraitano-myffu/omarchy-arm.git
cd omarchy-arm
./install.sh --dry-run    # print the whole plan, change nothing
./install.sh
```

It installs onto a machine that is already running Arch Linux ARM. Upstream
installs from an ISO and has no installer for a running system, so
`install.sh` is new here; porting the ISO would need a bootloader story per
board and is not done.

The `quattro` branch is upstream's, unmodified, so the whole port is
`git diff quattro arm64`. What changed, what it cost, and what still does not
work is in [`docs/arm64-port.md`](docs/arm64-port.md).

MIT, like upstream. The copyright in `LICENSE` stays David Heinemeier
Hansson's, and everything added here is contributed under the same terms. This
is an unofficial port and is not affiliated with Omarchy or Basecamp.

Everything below is upstream's README and still applies.

---

# Omarchy

Omarchy is a beautiful, modern & opinionated Linux distribution by DHH.

Read more at [omarchy.org](https://omarchy.org).

## The Omarchy Manual

The manual lives in [`manual/`](manual/), which is its authoritative source. It's
mirrored to [learn.omacom.io](https://learn.omacom.io/2/the-omarchy-manual), where
its screenshots are also hosted.

- [Welcome to Omarchy!](manual/01-welcome-to-omarchy.md)

**The Basics**

- [Getting Started](manual/02-getting-started.md)
- [Coming From Mac or Windows](manual/03-coming-from-mac-or-windows.md)
- [Navigation](manual/04-navigation.md)
- [The top bar](manual/05-the-top-bar.md)
- [Themes](manual/06-themes.md)
- [Hotkeys](manual/07-hotkeys.md)
- [Unified Clipboard & History](manual/08-unified-clipboard-history.md)
- [Reminders](manual/09-reminders.md)
- [Notices](manual/10-notices.md)
- [Text Extraction & Dictation](manual/11-text-extraction-dictation.md)
- [Screenshots & Recording](manual/12-screenshots-recording.md)
- [Toggles, idle & screensaver](manual/13-toggles-idle-screensaver.md)
- [Omarchy CLI](manual/14-omarchy-cli.md)

**The Applications**

- [Terminal](manual/15-terminal.md)
- [Neovim](manual/16-neovim.md)
- [AI](manual/17-ai.md)
- [Development Tools](manual/18-development-tools.md)
- [Shell Tools](manual/19-shell-tools.md)
- [Shell Functions](manual/20-shell-functions.md)
- [TUIs](manual/21-tuis.md)
- [GUIs](manual/22-guis.md)
- [Browsers](manual/23-browsers.md)
- [Commercial apps/services](manual/24-commercial-apps-services.md)
- [Web Apps](manual/25-web-apps.md)
- [Gaming](manual/26-gaming.md)
- [Filling out PDFs](manual/27-filling-out-pdfs.md)
- [Windows VM](manual/28-windows-vm.md)
- [Other Packages](manual/29-other-packages.md)

**Configuration**

- [Updates](manual/30-updates.md)
- [Dotfiles](manual/31-dotfiles.md)
- [Shell plugins](manual/32-shell-plugins.md)
- [Monitors](manual/33-monitors.md)
- [Keyboard, Mouse, Trackpad](manual/34-keyboard-mouse-trackpad.md)
- [Networking](manual/35-networking.md)
- [System sleep](manual/36-system-sleep.md)
- [Hardware authentication](manual/37-hardware-authentication.md)
- [Fonts](manual/38-fonts.md)
- [Backgrounds](manual/39-backgrounds.md)
- [Prompt](manual/40-prompt.md)
- [Branding](manual/41-branding.md)
- [Common tweaks](manual/42-common-tweaks.md)
- [Extra themes](manual/43-extra-themes.md)
- [Making your own theme](manual/44-making-your-own-theme.md)

**The Rest**

- [Mac support](manual/45-mac-support.md)
- [Troubleshooting](manual/46-troubleshooting.md)
- [FAQ](manual/47-faq.md)
- [System snapshots](manual/48-system-snapshots.md)
- [Security](manual/49-security.md)
- [Omarchy on...](manual/50-omarchy-on.md)
- [Dual Boot Install](manual/51-dual-boot-install.md)
- [Unattended Installs](manual/52-unattended-installs.md)

## License

Omarchy is released under the [MIT License](https://opensource.org/licenses/MIT).
