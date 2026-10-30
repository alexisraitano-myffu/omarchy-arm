# Gating note for the ARM64 fork: leaves wired with run_logged_x86 install
# drivers, firmware or kernels that only exist for x86_64. They are kept in
# place rather than deleted so this tree still rebases cleanly on upstream.
source "$OMARCHY_INSTALL/arm/platform.sh"

run_logged_x86 "$OMARCHY_INSTALL/hardware/asus-rog.sh"
run_logged_x86 "$OMARCHY_INSTALL/hardware/framework16.sh"
run_logged_x86 "$OMARCHY_INSTALL/hardware/dell-xps-touchpad-haptics.sh"
run_logged_x86 "$OMARCHY_INSTALL/hardware/surface.sh"

run_logged "$OMARCHY_INSTALL/hardware/network.sh"
run_logged "$OMARCHY_INSTALL/hardware/input-group.sh"
run_logged "$OMARCHY_INSTALL/hardware/set-wireless-regdom.sh"
run_logged "$OMARCHY_INSTALL/hardware/fix-fkeys.sh"
run_logged "$OMARCHY_INSTALL/hardware/fix-synaptic-touchpad.sh"
run_logged "$OMARCHY_INSTALL/hardware/bluetooth.sh"
run_logged_x86 "$OMARCHY_INSTALL/hardware/nvidia.sh"
# vulkan.sh matches GPU vendors on the PCI bus. Neither the Apple Silicon GPU
# nor the Pi's VideoCore VII is a PCI device, so the ARM leaves own Vulkan.
run_logged_x86 "$OMARCHY_INSTALL/hardware/vulkan.sh"
run_logged_arm "$OMARCHY_INSTALL/hardware/arm/vulkan.sh"
run_logged_arm "$OMARCHY_INSTALL/hardware/arm/apple-silicon.sh"
run_logged_arm "$OMARCHY_INSTALL/hardware/arm/raspberry-pi.sh"
run_logged_arm "$OMARCHY_INSTALL/hardware/arm/power-profiles.sh"
run_logged_arm "$OMARCHY_INSTALL/hardware/arm/cix-sky1.sh"

run_logged_x86 "$OMARCHY_INSTALL/hardware/intel/video-acceleration.sh"
run_logged_x86 "$OMARCHY_INSTALL/hardware/intel/lpmd.sh"
run_logged_x86 "$OMARCHY_INSTALL/hardware/intel/thermald.sh"
# Swap in the Panther Lake kernel before anything pulls DKMS modules in.
# intel-ipu7-camera drags in ipu7-drivers, vision-drivers and v4l2loopback,
# and building all three against the stock kernel only to rebuild them against
# linux-ptl and tear the first set down again cost ~25s of the install.
run_logged_x86 "$OMARCHY_INSTALL/hardware/intel/ptl-kernel.sh"
run_logged_x86 "$OMARCHY_INSTALL/hardware/intel/ipu7-camera.sh"
run_logged_x86 "$OMARCHY_INSTALL/hardware/intel/fred.sh"
run_logged_x86 "$OMARCHY_INSTALL/hardware/intel/fix-wifi7-eht.sh"
run_logged_x86 "$OMARCHY_INSTALL/hardware/intel/sof-firmware.sh"

run_logged_x86 "$OMARCHY_INSTALL/hardware/asus/fix-asus-ptl-display-backlight.sh"
run_logged_x86 "$OMARCHY_INSTALL/hardware/asus/fix-asus-ptl-b9406-display.sh"
run_logged_x86 "$OMARCHY_INSTALL/hardware/asus/fix-asus-ptl-b9406-touchpad.sh"
run_logged_x86 "$OMARCHY_INSTALL/hardware/asus/fix-z13-touchpad.sh"

run_logged_x86 "$OMARCHY_INSTALL/hardware/framework/qmk-hid.sh"

# These target Intel Macs with a T2 security chip, not Apple Silicon. The
# Apple Silicon quirks live in install/hardware/arm/apple-silicon.sh.
run_logged_x86 "$OMARCHY_INSTALL/hardware/apple/fix-spi-keyboard.sh"
run_logged_x86 "$OMARCHY_INSTALL/hardware/apple/fix-suspend-nvme.sh"
run_logged_x86 "$OMARCHY_INSTALL/hardware/apple/fix-t2.sh"
run_logged_x86 "$OMARCHY_INSTALL/hardware/apple/fix-brcmfmac-supplicant.sh"

run_logged_x86 "$OMARCHY_INSTALL/hardware/lenovo/fix-yoga-pro7-bass-speakers.sh"

run_logged_x86 "$OMARCHY_INSTALL/hardware/fix-bcm43xx.sh"
run_logged_x86 "$OMARCHY_INSTALL/hardware/fix-surface-keyboard.sh"
run_logged_x86 "$OMARCHY_INSTALL/hardware/fix-yt6801-ethernet-adapter.sh"
run_logged_x86 "$OMARCHY_INSTALL/hardware/fix-tuxedo-backlight.sh"
run_logged "$OMARCHY_INSTALL/hardware/speaker-tuning.sh"
run_logged_x86 "$OMARCHY_INSTALL/hardware/pacman.sh"
