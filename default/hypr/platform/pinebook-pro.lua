-- Pine64 Pinebook Pro defaults.
--
-- The Pinebook Pro's keyboard has no keypad: with numlock on, its embedded
-- keypad layer turns u i o j k l m and friends into digits. Omarchy's input
-- defaults switch numlock on at login, so on this machine every new keyboard
-- device came up typing the wrong characters until numlock was pressed.
--
-- A default, not a lock: ~/.config/hypr/input.lua loads after this file and
-- wins.

hl.config({
  input = {
    numlock_by_default = false,
  },
})
