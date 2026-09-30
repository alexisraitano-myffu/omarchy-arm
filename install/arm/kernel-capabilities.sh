# Adapt the install to what the running kernel can do.
#
# Arch Linux ARM machines often run a vendor kernel rather than an Arch one:
# the SoC's own tree is the only kernel with working display, NIC or storage
# drivers (the CIX Sky1 6.6 kernel on the Minisforum MS-R1 is one). Such
# kernels can lack features stock Arch assumes. Each function below keys on
# one missing feature, never on the board, and changes nothing when the
# kernel configuration cannot be read.
#
#   Landlock absent   pacman cannot build its download sandbox ("restricting
#                     filesystem access failed because Landlock is not
#                     supported by the kernel"), so every -Sy fails.
#   nf_tables absent  Arch's iptables is the nft backend, so ufw cannot load a
#                     single rule; the legacy backend still works.
#   zram absent       zram-generator waits 90 s for /dev/zram0 on every boot.
#
# Sourced by install.sh. Defines functions only. Honours OMARCHY_ARM_DRY_RUN=1.
# Test seams: OMARCHY_LSM_FILE, OMARCHY_KCONFIG (a plain or gzipped kernel
# config), OMARCHY_SYS_MODULE, OMARCHY_PACMAN_CONF, OMARCHY_ZRAM_DROPIN_DIR,
# OMARCHY_UFW_DEFAULTS.

# Print y, m or n for a kernel option, or nothing when the configuration is
# not readable (then every caller leaves the system alone).
omarchy_arm_kconfig() {
  local key="$1"
  local config="${OMARCHY_KCONFIG:-/proc/config.gz}"
  local line

  [[ -r $config ]] || return 0

  if [[ $config == *.gz ]]; then
    line=$(zcat "$config" 2>/dev/null | grep -E "^(# )?${key}[= ]" | head -n 1)
  else
    line=$(grep -E "^(# )?${key}[= ]" "$config" | head -n 1)
  fi

  case "$line" in
    "${key}=y") echo y ;;
    "${key}=m") echo m ;;
    *) echo n ;;
  esac
}

omarchy_arm_dry() {
  (( ${OMARCHY_ARM_DRY_RUN:-0} ))
}

# Run a command that writes $1 (a file or directory), through sudo only when
# the target is not writable as it stands. install.sh runs as the user; the
# tests point every path at a scratch directory and need no root.
omarchy_arm_write_as() {
  local target="$1"
  shift
  if [[ -w $target ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

# Landlock is listed in the active LSMs when pacman can use it.
omarchy_arm_pacman_without_landlock() {
  local lsm_file="${OMARCHY_LSM_FILE:-/sys/kernel/security/lsm}"
  local conf="${OMARCHY_PACMAN_CONF:-/etc/pacman.conf}"

  [[ -r $lsm_file && -f $conf ]] || return 0
  grep -q landlock "$lsm_file" && return 0
  grep -qE '^[[:space:]]*DisableSandboxFilesystem\b' "$conf" &&
    grep -qE '^[[:space:]]*DisableSandboxSyscalls\b' "$conf" && return 0

  echo "The kernel has no Landlock, which pacman's download sandbox needs."
  echo "Turning the sandbox off in $conf (DisableSandboxFilesystem, DisableSandboxSyscalls)."

  if omarchy_arm_dry; then
    echo "[dry-run] enable DisableSandboxFilesystem and DisableSandboxSyscalls in $conf"
    return 0
  fi

  local key
  for key in DisableSandboxFilesystem DisableSandboxSyscalls; do
    if grep -qE "^[[:space:]]*${key}\b" "$conf"; then
      continue
    elif grep -qE "^[[:space:]]*#[[:space:]]*${key}\b" "$conf"; then
      omarchy_arm_write_as "$conf" sed -i -E "s|^[[:space:]]*#[[:space:]]*${key}\b.*|${key}|" "$conf"
    else
      omarchy_arm_write_as "$conf" sed -i "/^\[options\]/a ${key}" "$conf"
    fi
  done
}

# Omarchy ships /usr/lib/systemd/zram-generator.conf.d/90-omarchy.conf. A file
# of the same name under /etc overrides it; an override with no [zram0]
# section asks for no device, so boot no longer waits for one.
omarchy_arm_zram_absent() {
  local dropin_dir="${OMARCHY_ZRAM_DROPIN_DIR:-/etc/systemd/zram-generator.conf.d}"
  local sys_module="${OMARCHY_SYS_MODULE:-/sys/module}"
  local zram

  zram=$(omarchy_arm_kconfig CONFIG_ZRAM)
  [[ $zram == n && ! -d $sys_module/zram ]] || return 0

  echo "The kernel has no zram (CONFIG_ZRAM is not set); disabling Omarchy's zram swap."

  if omarchy_arm_dry; then
    echo "[dry-run] write $dropin_dir/90-omarchy.conf with no zram device"
    return 0
  fi

  local parent
  parent=$(dirname "$dropin_dir")
  [[ -d $dropin_dir ]] || omarchy_arm_write_as "$parent" mkdir -p "$dropin_dir"
  omarchy_arm_write_as "$dropin_dir" tee "$dropin_dir/90-omarchy.conf" >/dev/null <<'CONF'
# Written by omarchy-arm: this kernel has no zram module (CONFIG_ZRAM is not
# set). Overrides /usr/lib/systemd/zram-generator.conf.d/90-omarchy.conf and
# defines no zram device. Delete this file after moving to a kernel with zram.
CONF
}

# Print the iptables backend this kernel needs: nft, legacy, or nothing when
# it cannot be told.
omarchy_arm_iptables_backend() {
  local nft legacy

  nft=$(omarchy_arm_kconfig CONFIG_NF_TABLES)
  legacy=$(omarchy_arm_kconfig CONFIG_IP_NF_IPTABLES)

  if [[ $nft == y || $nft == m ]]; then
    echo nft
  elif [[ $legacy == y || $legacy == m ]]; then
    echo legacy
  fi
}

omarchy_arm_iptables_for_kernel() {
  local ufw_defaults="${OMARCHY_UFW_DEFAULTS:-/etc/default/ufw}"
  local ip6

  [[ $(omarchy_arm_iptables_backend) == legacy ]] || return 0

  echo "The kernel has no nf_tables but has legacy iptables; ufw needs iptables-legacy."

  if omarchy_arm_dry; then
    echo "[dry-run] sudo pacman -S iptables-legacy (replaces iptables)"
  elif ! pacman -Qq iptables-legacy >/dev/null 2>&1; then
    # iptables-legacy conflicts with iptables; the answer to "remove
    # iptables?" is the only question pacman asks here.
    yes | sudo pacman -S --needed iptables-legacy
  fi

  ip6=$(omarchy_arm_kconfig CONFIG_IP6_NF_IPTABLES)
  if [[ $ip6 != y && $ip6 != m && -f $ufw_defaults ]]; then
    echo "No IPv6 iptables either; ufw filters IPv4 only (IPV6=no in $ufw_defaults)."
    if omarchy_arm_dry; then
      echo "[dry-run] set IPV6=no in $ufw_defaults"
    else
      omarchy_arm_write_as "$ufw_defaults" sed -i 's/^IPV6=yes/IPV6=no/' "$ufw_defaults"
    fi
  fi
}
