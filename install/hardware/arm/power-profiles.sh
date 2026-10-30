# Give power-profiles-daemon's profiles an effect on aarch64.
#
# ppd works through EPP and ACPI platform_profile, which only x86 machines
# have. On an aarch64 laptop or board it loads its placeholder driver, offers
# balanced and power-saver, and switching between them changes nothing: the
# Omarchy power menu and the battery switch in the shell are no-ops there.
# omarchy-powerprofiles-tune applies power-saver with generic knobs (cpufreq
# boost, PCIe ASPM policy, Wi-Fi power save) and restores them for balanced.
# A path unit runs it whenever ppd writes its state file, so every client
# (the shell, powerprofilesctl, a GNOME panel) triggers it and nothing polls.
#
# Test seams: OMARCHY_SYSTEMD_SYSTEM_DIR, OMARCHY_NM_DISPATCHER_DIR.

unit_dir="${OMARCHY_SYSTEMD_SYSTEM_DIR:-/etc/systemd/system}"
dispatcher_dir="${OMARCHY_NM_DISPATCHER_DIR:-/etc/NetworkManager/dispatcher.d}"

for unit in omarchy-powerprofiles-tune.path omarchy-powerprofiles-tune.service; do
  install -Dm644 "$OMARCHY_PATH/default/systemd/system/$unit" "$unit_dir/$unit"
done
install -Dm755 "$OMARCHY_PATH/default/NetworkManager/dispatcher.d/90-omarchy-powerprofiles-tune" \
  "$dispatcher_dir/90-omarchy-powerprofiles-tune"

systemctl enable omarchy-powerprofiles-tune.path omarchy-powerprofiles-tune.service
