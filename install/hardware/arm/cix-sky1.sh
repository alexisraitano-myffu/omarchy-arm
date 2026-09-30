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
# Test seams: OMARCHY_SYS_MODULE, OMARCHY_ENVIRONMENT_FILE.

source "$OMARCHY_INSTALL/arm/platform.sh"

omarchy-hw-cix-sky1 || return 0

sys_module="${OMARCHY_SYS_MODULE:-/sys/module}"
environment="${OMARCHY_ENVIRONMENT_FILE:-/etc/environment}"

if [[ -d $sys_module/panthor ]]; then
  echo "panthor is loaded: Mesa drives the Mali GPU, no software rendering needed."
  return 0
fi

if grep -q '^LIBGL_ALWAYS_SOFTWARE=' "$environment" 2>/dev/null; then
  return 0
fi

echo "No Mesa driver for this kernel's display and GPU: Hyprland renders with llvmpipe."
echo "LIBGL_ALWAYS_SOFTWARE=1" >>"$environment"
