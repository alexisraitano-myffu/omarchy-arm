echo "Start omarchy-powerprofiles-tune at boot again (ordering cycle with power-profiles-daemon)"

unit=/etc/systemd/system/omarchy-powerprofiles-tune.service
if [[ -f $unit ]]; then
  sudo install -Dm644 "$OMARCHY_PATH/default/systemd/system/omarchy-powerprofiles-tune.service" "$unit"
  sudo systemctl daemon-reload
  sudo systemctl reenable omarchy-powerprofiles-tune.service
fi
