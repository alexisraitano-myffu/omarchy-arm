#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

source "$ROOT/install/arm/kernel-capabilities.sh"

# The kernel options below are exactly what the CIX Sky1 vendor kernel
# (6.6.10-cix-build-generic on the Minisforum MS-R1) reports.
vendor_config="$test_tmp/vendor.config"
cat >"$vendor_config" <<'CONFIG'
# CONFIG_ZRAM is not set
# CONFIG_NF_TABLES is not set
CONFIG_NETFILTER_XTABLES=y
CONFIG_IP_NF_IPTABLES=y
CONFIG_IP6_NF_IPTABLES=y
CONFIG
gzip -c "$vendor_config" >"$test_tmp/vendor.config.gz"

stock_config="$test_tmp/stock.config"
cat >"$stock_config" <<'CONFIG'
CONFIG_ZRAM=m
CONFIG_NF_TABLES=m
CONFIG_IP_NF_IPTABLES=m
CONFIG_IP6_NF_IPTABLES=m
CONFIG

# --- the configuration reader --------------------------------------------

[[ $(OMARCHY_KCONFIG="$vendor_config" omarchy_arm_kconfig CONFIG_ZRAM) == n ]] ||
  fail "an unset option reads as n"
pass "an unset option reads as n"

[[ $(OMARCHY_KCONFIG="$test_tmp/vendor.config.gz" omarchy_arm_kconfig CONFIG_IP_NF_IPTABLES) == y ]] ||
  fail "a gzipped configuration (/proc/config.gz) is read"
pass "a gzipped configuration (/proc/config.gz) is read"

[[ $(OMARCHY_KCONFIG="$stock_config" omarchy_arm_kconfig CONFIG_NF_TABLES) == m ]] ||
  fail "a module reads as m"
pass "a module reads as m"

[[ -z $(OMARCHY_KCONFIG="$test_tmp/absent" omarchy_arm_kconfig CONFIG_ZRAM) ]] ||
  fail "an unreadable configuration reads as nothing"
pass "an unreadable configuration reads as nothing"

# --- pacman without Landlock ---------------------------------------------

conf="$test_tmp/pacman.conf"
reset_pacman_conf() {
  cat >"$conf" <<'CONF'
[options]
ParallelDownloads = 5
DownloadUser = alpm
#DisableSandboxFilesystem
#DisableSandboxSyscalls

[core]
Include = /etc/pacman.d/mirrorlist
CONF
}

reset_pacman_conf
echo "capability" >"$test_tmp/lsm-vendor"
OMARCHY_LSM_FILE="$test_tmp/lsm-vendor" OMARCHY_PACMAN_CONF="$conf" omarchy_arm_pacman_without_landlock >/dev/null
grep -qx 'DisableSandboxFilesystem' "$conf" && grep -qx 'DisableSandboxSyscalls' "$conf" ||
  fail "a kernel without Landlock turns pacman's sandbox off" "$(cat "$conf")"
pass "a kernel without Landlock turns pacman's sandbox off"

OMARCHY_LSM_FILE="$test_tmp/lsm-vendor" OMARCHY_PACMAN_CONF="$conf" omarchy_arm_pacman_without_landlock >/dev/null
[[ $(grep -c '^DisableSandbox' "$conf") == 2 ]] || fail "running it twice changes nothing" "$(cat "$conf")"
pass "running it twice changes nothing"

[[ -z $(OMARCHY_LSM_FILE="$test_tmp/lsm-vendor" OMARCHY_PACMAN_CONF="$conf" omarchy_arm_pacman_without_landlock) ]] ||
  fail "a sandbox already turned off is not announced again"
pass "a sandbox already turned off is not announced again"

reset_pacman_conf
echo "capability,landlock,yama,bpf" >"$test_tmp/lsm-stock"
OMARCHY_LSM_FILE="$test_tmp/lsm-stock" OMARCHY_PACMAN_CONF="$conf" omarchy_arm_pacman_without_landlock >/dev/null
grep -q '^DisableSandbox' "$conf" && fail "a kernel with Landlock keeps the sandbox" "$(cat "$conf")"
pass "a kernel with Landlock keeps the sandbox"

reset_pacman_conf
OMARCHY_ARM_DRY_RUN=1 OMARCHY_LSM_FILE="$test_tmp/lsm-vendor" OMARCHY_PACMAN_CONF="$conf" omarchy_arm_pacman_without_landlock >/dev/null
grep -q '^DisableSandbox' "$conf" && fail "a dry run leaves pacman.conf alone"
pass "a dry run leaves pacman.conf alone"

# --- zram ----------------------------------------------------------------

mkdir -p "$test_tmp/sys-module-empty" "$test_tmp/sys-module-zram/zram"

dropins="$test_tmp/zram.conf.d"
OMARCHY_KCONFIG="$vendor_config" OMARCHY_SYS_MODULE="$test_tmp/sys-module-empty" \
  OMARCHY_ZRAM_DROPIN_DIR="$dropins" omarchy_arm_zram_absent >/dev/null
[[ -f $dropins/90-omarchy.conf ]] || fail "a kernel without zram gets the empty override"
grep -q '^\[zram0\]' "$dropins/90-omarchy.conf" && fail "the override defines no zram device"
pass "a kernel without zram gets an override that defines no device"

rm -rf "$dropins"
OMARCHY_KCONFIG="$stock_config" OMARCHY_SYS_MODULE="$test_tmp/sys-module-empty" \
  OMARCHY_ZRAM_DROPIN_DIR="$dropins" omarchy_arm_zram_absent >/dev/null
[[ -e $dropins ]] && fail "a kernel with a zram module keeps Omarchy's zram swap"
pass "a kernel with a zram module keeps Omarchy's zram swap"

OMARCHY_KCONFIG="$test_tmp/absent" OMARCHY_SYS_MODULE="$test_tmp/sys-module-empty" \
  OMARCHY_ZRAM_DROPIN_DIR="$dropins" omarchy_arm_zram_absent >/dev/null
[[ -e $dropins ]] && fail "an unreadable configuration changes nothing"
pass "an unreadable configuration changes nothing"

# --- iptables backend ----------------------------------------------------

[[ $(OMARCHY_KCONFIG="$vendor_config" omarchy_arm_iptables_backend) == legacy ]] ||
  fail "no nf_tables with legacy iptables asks for iptables-legacy"
pass "no nf_tables with legacy iptables asks for iptables-legacy"

[[ $(OMARCHY_KCONFIG="$stock_config" omarchy_arm_iptables_backend) == nft ]] ||
  fail "a kernel with nf_tables keeps the nft backend"
pass "a kernel with nf_tables keeps the nft backend"

[[ -z $(OMARCHY_KCONFIG="$test_tmp/absent" omarchy_arm_iptables_backend) ]] ||
  fail "an unreadable configuration names no backend"
pass "an unreadable configuration names no backend"

ufw_defaults="$test_tmp/ufw"
printf 'IPV6=yes\nDEFAULT_INPUT_POLICY="DROP"\n' >"$ufw_defaults"
no_ip6="$test_tmp/no-ip6.config"
grep -v IP6_NF "$vendor_config" >"$no_ip6"
echo "# CONFIG_IP6_NF_IPTABLES is not set" >>"$no_ip6"
OMARCHY_ARM_DRY_RUN=1 OMARCHY_KCONFIG="$no_ip6" OMARCHY_UFW_DEFAULTS="$ufw_defaults" \
  omarchy_arm_iptables_for_kernel | grep -q 'set IPV6=no' ||
  fail "without IPv6 iptables the dry run plans IPv4-only ufw"
grep -q '^IPV6=yes' "$ufw_defaults" || fail "the dry run leaves ufw's defaults alone"
pass "without IPv6 iptables ufw is planned IPv4-only, and a dry run changes nothing"
