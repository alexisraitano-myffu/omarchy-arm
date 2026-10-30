-- Platform tuning for the ARM64 fork.
--
-- Loaded after default/hypr/looknfeel.lua and default/hypr/input.lua, and
-- before the user's own ~/.config/hypr files, so a board's defaults can be sensible without
-- taking the choice away from anyone who wants the full look back.
--
-- Detection shells out to the same predicates the install tree uses, the way
-- default/hypr/nvidia.lua does, rather than duplicating the device-tree
-- parsing in Lua.
--
-- Apple Silicon has no entry: its GPU runs the stock look at full speed, and
-- HiDPI is already handled by the shipped monitors.lua, which asks Hyprland
-- for scale = "auto".

local paths = require("default.hypr.paths")
local require_optional = require("default.hypr.require_optional")

if o.shell_succeeds(o.shell_quote(paths.omarchy_path .. "/bin/omarchy-hw-raspberry-pi")) then
  require_optional.module("default.hypr.platform.raspberry-pi")
elseif o.shell_succeeds(o.shell_quote(paths.omarchy_path .. "/bin/omarchy-hw-pinebook-pro")) then
  require_optional.module("default.hypr.platform.pinebook-pro")
end
