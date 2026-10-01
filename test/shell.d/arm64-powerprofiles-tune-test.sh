#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mkdir -p "$test_tmp/bin"

# iw stand-in: power save state lives in one file per interface.
cat >"$test_tmp/bin/iw" <<'EOF'
#!/bin/bash
dev="$2"
case "$3 $4" in
  "get power_save") echo "Power save: $(<"$IW_STATE/$dev")" ;;
  "set power_save") echo "$5" >"$IW_STATE/$dev" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$test_tmp/bin/iw"

export PATH="$test_tmp/bin:$ROOT/bin:$PATH"
export IW_STATE="$test_tmp/iw"
export OMARCHY_PPD_STATE="$test_tmp/state.ini"
export OMARCHY_SYS_CPUFREQ="$test_tmp/cpufreq"
export OMARCHY_SYS_PCIE_ASPM="$test_tmp/aspm-policy"
export OMARCHY_SYS_NET="$test_tmp/net"
export OMARCHY_POWERPROFILES_RUN_DIR="$test_tmp/run"

reset_machine() {
  rm -rf "$test_tmp/cpufreq" "$test_tmp/net" "$test_tmp/iw" "$test_tmp/run"
  mkdir -p "$test_tmp/cpufreq" "$test_tmp/net/wlan0/phy80211" "$test_tmp/net/eth0" "$test_tmp/iw"
  echo 1 >"$test_tmp/cpufreq/boost"
  echo "[default] performance powersave powersupersave" >"$test_tmp/aspm-policy"
  chmod 644 "$test_tmp/aspm-policy"
  echo off >"$test_tmp/iw/wlan0"
}

ppd_state() {
  printf '[State]\nbattery_aware=true\nPlatformDriver=placeholder\n%sProfile=%s\n' "${2:-}" "$1" >"$test_tmp/state.ini"
}

tune() {
  omarchy-powerprofiles-tune "$@" >/dev/null
}

reset_machine
ppd_state power-saver
tune
[[ $(<"$test_tmp/cpufreq/boost") == 0 ]] || fail "power-saver turns cpufreq boost off"
[[ $(<"$test_tmp/aspm-policy") == "powersupersave" ]] || fail "power-saver selects the deepest ASPM policy"
[[ $(<"$test_tmp/iw/wlan0") == "on" ]] || fail "power-saver turns Wi-Fi power save on"
[[ ! -e $test_tmp/iw/eth0 ]] || fail "a wired interface is not touched"
pass "power-saver turns boost off, ASPM to powersupersave and Wi-Fi power save on"

# A second power-saver run (NetworkManager's dispatcher after a reconnect)
# must not record power-saver's own values as the ones to restore.
echo off >"$test_tmp/iw/wlan0"
tune
[[ $(<"$test_tmp/run/boost") == 1 && $(<"$test_tmp/run/wifi-wlan0") == "off" ]] ||
  fail "running power-saver again keeps the original values" "$(grep -r . "$test_tmp/run")"
[[ $(<"$test_tmp/iw/wlan0") == "on" ]] || fail "power-saver turns Wi-Fi power save back on after a reconnect"
pass "running power-saver again keeps the original values"

ppd_state balanced
tune
[[ $(<"$test_tmp/cpufreq/boost") == 1 ]] || fail "balanced restores boost"
[[ $(<"$test_tmp/aspm-policy") == "default" ]] || fail "balanced restores the ASPM policy"
[[ $(<"$test_tmp/iw/wlan0") == "off" ]] || fail "balanced restores Wi-Fi power save"
[[ -z $(ls -A "$test_tmp/run") ]] || fail "balanced leaves nothing saved" "$(ls -A "$test_tmp/run")"
pass "balanced restores what power-saver changed"

reset_machine
echo 0 >"$test_tmp/cpufreq/boost"
tune balanced
[[ $(<"$test_tmp/cpufreq/boost") == 0 ]] || fail "balanced keeps the platform's own boost setting"
[[ $(<"$test_tmp/aspm-policy") == "[default] performance powersave powersupersave" ]] ||
  fail "balanced with nothing saved writes nothing"
pass "balanced with nothing saved keeps the platform defaults"

reset_machine
ppd_state power-saver $'CpuDriver=amd_pstate\n'
tune
[[ $(<"$test_tmp/cpufreq/boost") == 1 ]] || fail "boost is left to ppd when it drives the CPU"
pass "boost is left to ppd when it has a CPU driver"

if (( EUID != 0 )); then
  reset_machine
  chmod 444 "$test_tmp/aspm-policy"
  tune power-saver
  [[ ! -e $test_tmp/run/aspm ]] || fail "ASPM turned off at boot is not recorded as changed"
  pass "ASPM turned off at boot is left alone"
fi

if omarchy-powerprofiles-tune turbo 2>/dev/null; then
  fail "an unknown profile is refused"
fi
pass "an unknown profile is refused"

# The install leaf: units and the dispatcher hook land where systemd and
# NetworkManager read them, and both units are enabled.
cat >"$test_tmp/bin/systemctl" <<'EOF'
#!/bin/bash
echo "$*" >>"$SYSTEMCTL_LOG"
EOF
chmod +x "$test_tmp/bin/systemctl"

(
  SYSTEMCTL_LOG="$test_tmp/systemctl.log" OMARCHY_PATH="$ROOT" \
    OMARCHY_SYSTEMD_SYSTEM_DIR="$test_tmp/etc/systemd/system" \
    OMARCHY_NM_DISPATCHER_DIR="$test_tmp/etc/NetworkManager/dispatcher.d" \
    source "$ROOT/install/hardware/arm/power-profiles.sh"
) >/dev/null
for unit in omarchy-powerprofiles-tune.path omarchy-powerprofiles-tune.service; do
  cmp -s "$ROOT/default/systemd/system/$unit" "$test_tmp/etc/systemd/system/$unit" || fail "$unit is installed"
done
[[ -x $test_tmp/etc/NetworkManager/dispatcher.d/90-omarchy-powerprofiles-tune ]] ||
  fail "the NetworkManager dispatcher hook is installed and executable"
grep -qx "enable omarchy-powerprofiles-tune.path omarchy-powerprofiles-tune.service" "$test_tmp/systemctl.log" ||
  fail "both units are enabled" "$(cat "$test_tmp/systemctl.log")"
grep -qx "PathChanged=/var/lib/power-profiles-daemon/state.ini" "$ROOT/default/systemd/system/omarchy-powerprofiles-tune.path" ||
  fail "the path unit watches ppd's state file"
pass "the install leaf places and enables the units and the dispatcher hook"
