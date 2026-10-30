# Install the Vulkan driver matching the aarch64 GPU.
#
# The x86 leaf (install/hardware/vulkan.sh) matches GPU vendors on the PCI bus.
# Neither the Apple Silicon GPU nor the Pi's VideoCore VII is a PCI device, so
# they are matched from the device tree instead.

source "$OMARCHY_INSTALL/arm/platform.sh"

case "$(omarchy-hw-platform)" in
  apple-silicon)
    omarchy_arm_pkg_add_available vulkan-asahi
    ;;
  raspberry-pi-5|raspberry-pi)
    # V3DV, Mesa's Vulkan driver for VideoCore.
    omarchy_arm_pkg_add_available vulkan-broadcom
    ;;
  cix-sky1)
    # The vendor kernel drives the Mali-G720 with mali_kbase, which Mesa cannot
    # use; the software rasterizer is the Vulkan device Hyprland gets.
    omarchy_arm_pkg_add_available vulkan-swrast
    ;;
  pinebook-pro)
    # The Mali-T860 is a Midgard GPU, which no Mesa Vulkan driver covers (PanVK
    # starts at Bifrost). Hyprland renders through panfrost's GLES, so there is
    # nothing to install -- and the generic branch below would add virtio-gpu
    # drivers this machine cannot use.
    ;;
  generic-aarch64)
    # A VM with no accelerated GPU: virtio-gpu with Venus, and the software
    # rasterizer as the fallback that keeps Hyprland able to start at all.
    omarchy_arm_pkg_add_available vulkan-virtio vulkan-swrast
    ;;
esac
