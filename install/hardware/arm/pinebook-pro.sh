# Pine64 Pinebook Pro (RK3399) quirks.
#
# The kernel defaults the RK3399 to "deep" suspend, and on the Pinebook Pro a
# deep resume is a coin toss: the log stops at "PM: suspend entry (deep)" and
# the machine needs a hard power-off. s2idle keeps the SoC in its idle states
# instead; it drains more battery with the lid shut but wakes every time, and
# within a couple of seconds.
#
# A systemd drop-in rather than mem_sleep_default= on the kernel command line,
# because the boot chain is not this fork's to touch (docs/arm64-port.md).

source "$OMARCHY_INSTALL/arm/platform.sh"

[[ $(omarchy-hw-platform) == "pinebook-pro" ]] || return 0

sudo mkdir -p /etc/systemd/sleep.conf.d
printf '[Sleep]\nMemorySleepMode=s2idle\n' |
  sudo tee /etc/systemd/sleep.conf.d/50-omarchy-pinebook-pro.conf >/dev/null
