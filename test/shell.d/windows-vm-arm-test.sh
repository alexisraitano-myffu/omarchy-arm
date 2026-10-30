#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

# gum answers every prompt with its default and records what it was asked.
cat >"$stub_bin/gum" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$GUM_LOG"
case "$1" in
  choose)
    cat >/dev/null
    for arg in "$@"; do
      [[ $arg == --selected=* ]] && echo "${arg#--selected=}"
    done
    ;;
  input)
    for arg in "$@"; do
      [[ $arg == --value=* ]] && echo "${arg#--value=}"
    done
    ;;
  confirm) exit 0 ;;
  style) printf '%s\n' "$@" ;;
esac
exit 0
STUB

# The container is up on the default bridge at 172.17.0.2 and has booted.
cat >"$stub_bin/docker" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$DOCKER_LOG"
case "$*" in
  *State.Status*) echo running ;;
  *State.StartedAt*) echo 2026-10-01T00:00:00Z ;;
  *IPAddress*) echo 172.17.0.2 ;;
  logs*) echo "Windows started successfully" ;;
esac
exit 0
STUB

cat >"$stub_bin/df" <<'STUB'
#!/bin/bash
echo "Filesystem 1K-blocks Used Available Use% Mounted"
echo "/dev/root 1000000000 0 500000000 0% /"
STUB

cat >"$stub_bin/nproc" <<'STUB'
#!/bin/bash
echo 12
STUB

cat >"$stub_bin/hyprctl" <<'STUB'
#!/bin/bash
echo '[{"focused": true, "scale": 1.0}]'
STUB

cat >"$stub_bin/xfreerdp3" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$RDP_LOG"
STUB

cat >"$stub_bin/xdg-open" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$OPEN_LOG"
STUB

for quiet in docker-compose omarchy-pkg-add omarchy-notification-send sleep timedatectl; do
  printf '#!/bin/bash\nexit 0\n' >"$stub_bin/$quiet"
done
chmod +x "$stub_bin"/*

export PATH="$stub_bin:$ROOT/bin:$PATH"
export OMARCHY_PATH="$ROOT"
export GUM_LOG="$test_tmp/gum.log" DOCKER_LOG="$test_tmp/docker.log"
export RDP_LOG="$test_tmp/rdp.log" OPEN_LOG="$test_tmp/open.log"

# CPU sysfs as the CIX Sky1 (Minisforum MS-R1) reports it: eight Cortex-A720
# (cpu0 and cpu5-11, at four different clocks) and four Cortex-A520.
make_cpus() {
  local root="$1"
  shift
  local cpu=0 spec
  for spec in "$@"; do
    mkdir -p "$root/cpu$cpu/regs/identification"
    echo "${spec%:*}" >"$root/cpu$cpu/regs/identification/midr_el1"
    echo "${spec#*:}" >"$root/cpu$cpu/cpu_capacity"
    cpu=$((cpu + 1))
  done
}

a720=0x00000000410fd811
a520=0x00000000410fd801
make_cpus "$test_tmp/sky1" "$a720:1024" "$a520:278" "$a520:278" "$a520:278" "$a520:278" \
  "$a720:905" "$a720:905" "$a720:866" "$a720:866" "$a720:984" "$a720:984" "$a720:1024"
make_cpus "$test_tmp/even" "$a720:1024" "$a720:1024" "$a720:1024" "$a720:1024"

# The Sky1 6.18 kernel: NAT for masquerading, but no xt_nat for DNAT.
cat >"$test_tmp/no-xt-nat.config" <<'CONFIG'
CONFIG_KVM=y
CONFIG_NF_NAT=m
CONFIG_NETFILTER_XT_TARGET_MASQUERADE=m
CONFIG
gzip -c "$test_tmp/no-xt-nat.config" >"$test_tmp/no-xt-nat.config.gz"

cat >"$test_tmp/stock.config" <<'CONFIG'
CONFIG_KVM=y
CONFIG_NF_NAT=m
CONFIG_NETFILTER_XT_NAT=m
CONFIG

touch "$test_tmp/kvm"

install_vm() {
  local home="$1"
  shift
  mkdir -p "$home"
  : >"$GUM_LOG"
  : >"$OPEN_LOG"
  env HOME="$home" OMARCHY_KVM_DEVICE="$test_tmp/kvm" "$@" \
    "$ROOT/bin/omarchy-windows-vm" install >"$home/out" 2>&1
}

compose() {
  cat "$1/.config/windows/docker-compose.yml"
}

# --- an MS-R1 on its own kernel ------------------------------------------

home="$test_tmp/sky1-home"
install_vm "$home" OMARCHY_ARCH=aarch64 OMARCHY_CPU_SYSFS="$test_tmp/sky1" \
  OMARCHY_KCONFIG="$test_tmp/no-xt-nat.config.gz" ||
  fail "the install finishes on a big.LITTLE ARM machine" "$(cat "$home/out")"
pass "the install finishes on a big.LITTLE ARM machine"

grep -q 'CPU cores (1-8)' "$GUM_LOG" ||
  fail "only the eight fastest identical cores are offered" "$(cat "$GUM_LOG")"
pass "only the eight fastest identical cores are offered"

compose "$home" | grep -qx '    image: dockurr/windows' ||
  fail "the multi-arch image is kept (its arm64 build is windows-arm)" "$(compose "$home")"
pass "the multi-arch image is kept (its arm64 build is windows-arm)"

compose "$home" | grep -qx '    network_mode: bridge' ||
  fail "a kernel without xt_nat puts the VM on the default bridge" "$(compose "$home")"
pass "a kernel without xt_nat puts the VM on the default bridge"

if compose "$home" | grep -q 'ports:'; then
  fail "a kernel without xt_nat publishes no ports" "$(compose "$home")"
fi
pass "a kernel without xt_nat publishes no ports"

if compose "$home" | grep -q driftfix; then
  fail "the x86-only RTC drift fix is left out on ARM" "$(compose "$home")"
fi
compose "$home" | grep -qx '      ARGUMENTS: "-rtc base=localtime,clock=host"' ||
  fail "the guest clock still follows the host on ARM" "$(compose "$home")"
pass "the x86-only RTC drift fix is left out on ARM"

compose "$home" | grep -qx '      VGA: "virtio-gpu"' ||
  fail "ARM uses virtio-gpu rather than the fixed-size ramfb" "$(compose "$home")"
pass "ARM uses virtio-gpu rather than the fixed-size ramfb"

grep -qx 'http://172.17.0.2:8006' "$OPEN_LOG" ||
  fail "the installer opens the viewer on the container's address" "$(cat "$OPEN_LOG")"
pass "the installer opens the viewer on the container's address"

: >"$RDP_LOG"
HOME="$home" "$ROOT/bin/omarchy-windows-vm" launch --keep-alive >"$home/launch" 2>&1 ||
  fail "launch connects on the bridge" "$(cat "$home/launch")"
grep -q '/v:172.17.0.2:3389' "$RDP_LOG" ||
  fail "RDP goes to the container's address" "$(cat "$RDP_LOG")"
pass "RDP goes to the container's address"

HOME="$home" "$ROOT/bin/omarchy-windows-vm" status | grep -q 'http://172.17.0.2:8006' ||
  fail "status names the container's address"
pass "status names the container's address"

# --- an ARM machine whose kernel can publish ports -----------------------

home="$test_tmp/stock-home"
install_vm "$home" OMARCHY_ARCH=aarch64 OMARCHY_CPU_SYSFS="$test_tmp/even" \
  OMARCHY_KCONFIG="$test_tmp/stock.config" ||
  fail "the install finishes on a homogeneous ARM machine" "$(cat "$home/out")"

grep -q 'CPU cores (1-4)' "$GUM_LOG" ||
  fail "every core is offered when all cores are identical" "$(cat "$GUM_LOG")"
pass "every core is offered when all cores are identical"

compose "$home" | grep -qx '      - 127.0.0.1:3389:3389/tcp' ||
  fail "a kernel with xt_nat publishes RDP on localhost" "$(compose "$home")"
pass "a kernel with xt_nat publishes RDP on localhost"

grep -qx 'http://127.0.0.1:8006' "$OPEN_LOG" ||
  fail "published ports are used through localhost" "$(cat "$OPEN_LOG")"
pass "published ports are used through localhost"

: >"$RDP_LOG"
HOME="$home" "$ROOT/bin/omarchy-windows-vm" launch --keep-alive >/dev/null 2>&1
grep -q '/v:127.0.0.1:3389' "$RDP_LOG" ||
  fail "RDP goes to localhost when its port is published" "$(cat "$RDP_LOG")"
pass "RDP goes to localhost when its port is published"

# --- x86 is untouched -----------------------------------------------------

home="$test_tmp/x86-home"
install_vm "$home" OMARCHY_ARCH=x86_64 OMARCHY_CPU_SYSFS="$test_tmp/sky1" \
  OMARCHY_KCONFIG="$test_tmp/no-xt-nat.config" ||
  fail "the install finishes on x86" "$(cat "$home/out")"

grep -q 'CPU cores (1-12)' "$GUM_LOG" ||
  fail "x86 offers every core" "$(cat "$GUM_LOG")"
compose "$home" | grep -q 'driftfix=slew' ||
  fail "x86 keeps the RTC drift fix" "$(compose "$home")"
if compose "$home" | grep -q 'VGA:'; then
  fail "x86 keeps the image's display default" "$(compose "$home")"
fi
compose "$home" | grep -qx '      - 127.0.0.1:8006:8006' ||
  fail "x86 publishes its ports whatever the kernel config says" "$(compose "$home")"
pass "x86 keeps its cores, drift fix, display and published ports"

# --- no KVM -------------------------------------------------------------

home="$test_tmp/nokvm-home"
mkdir -p "$home"
if HOME="$home" OMARCHY_ARCH=aarch64 OMARCHY_KVM_DEVICE="$test_tmp/absent" \
  "$ROOT/bin/omarchy-windows-vm" install >"$home/out" 2>&1; then
  fail "the install stops without KVM"
fi
grep -q 'EL2' "$home/out" && ! grep -q 'kvm-intel' "$home/out" ||
  fail "ARM is told about EL2, not x86 modules" "$(cat "$home/out")"
pass "ARM is told about EL2, not x86 modules"
