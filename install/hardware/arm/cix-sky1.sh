# CIX Sky1 quirks (Minisforum MS-R1, Radxa Orion O6).
#
# On the vendor kernel the display engines are `linlondp` KMS devices (one DRM
# card per output) and the Mali-G720 is driven by the proprietary mali_kbase.
# Mesa has a driver for neither, so EGL fails with "failed to create dri2
# screen" on every card and Hyprland aborts before the first frame -- the SDDM
# greeter included, since it is a Hyprland compositor too. Mesa's kms_swrast
# path (llvmpipe) drives the linlondp cards fine: a 4K desktop idles at a load
# under 2 on the Cortex-A720s.
#
# pam_env reads /etc/environment for both the greeter and the user session,
# which is why the switch lives there. A kernel with the upstream panthor
# driver gets Mesa's own GPU driver instead, and this leaf leaves it alone.
#
# On a device-tree kernel (Sky1-Linux) the CPUs run under scmi-cpufreq, which
# files the A720s' upper operating points (2.0-2.6 GHz) as boost and starts
# with boost off: the big cores sit at 1.9 GHz, 37% below the vendor kernel
# on one thread. Every A720 pair has a thermal zone (passive trips at 60 and
# 85 C) bound to its cpufreq cooling device, so turning boost on is safe: a
# 12-core stress run holds full boost at 54 C on an MS-R1.
#
# Test seams: OMARCHY_SYS_MODULE, OMARCHY_ENVIRONMENT_FILE, OMARCHY_SYS_CPUFREQ,
# OMARCHY_TMPFILES_DIR.

source "$OMARCHY_INSTALL/arm/platform.sh"

omarchy-hw-cix-sky1 || return 0

sys_module="${OMARCHY_SYS_MODULE:-/sys/module}"
environment="${OMARCHY_ENVIRONMENT_FILE:-/etc/environment}"
sys_cpufreq="${OMARCHY_SYS_CPUFREQ:-/sys/devices/system/cpu/cpufreq}"
tmpfiles="${OMARCHY_TMPFILES_DIR:-/etc/tmpfiles.d}"

if [[ -f $sys_cpufreq/boost && $(cat "$sys_cpufreq/policy0/scaling_driver" 2>/dev/null) == scmi ]]; then
  echo "scmi-cpufreq: enabling the A720 boost operating points."
  echo "w /sys/devices/system/cpu/cpufreq/boost - - - - 1" >"$tmpfiles/cix-sky1-cpufreq-boost.conf"
  echo 1 >"$sys_cpufreq/boost" 2>/dev/null || true
fi

if [[ -d $sys_module/panthor ]]; then
  echo "panthor is loaded: Mesa drives the Mali GPU, no software rendering needed."
  return 0
fi

if grep -q '^LIBGL_ALWAYS_SOFTWARE=' "$environment" 2>/dev/null; then
  return 0
fi

echo "No Mesa driver for this kernel's display and GPU: Hyprland renders with llvmpipe."
echo "LIBGL_ALWAYS_SOFTWARE=1" >>"$environment"
