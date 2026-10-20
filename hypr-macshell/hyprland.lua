-- This file sources other files in `hyprland` and `custom` folders
-- You wanna add your stuff in files in `custom`

-- Internal stuff --
require("hyprland.lib")
require("hyprland.services")

-- Environment variables --
require("hyprland.env")
if is_file_exists(HOME .. "/.config/hypr-macshell/custom/env.lua") then
    require("custom.env")
end

-- Default configurations --
require("hyprland.execs")
require("hyprland.general")
require("hyprland.rules")
require("hyprland.colors")
require("hyprland.keybinds")

-- Custom configurations --
if is_file_exists(HOME .. "/.config/hypr-macshell/custom/execs.lua") then
    require("custom.execs")
end
if is_file_exists(HOME .. "/.config/hypr-macshell/custom/general.lua") then
    require("custom.general")
end
if is_file_exists(HOME .. "/.config/hypr-macshell/custom/rules.lua") then
    require("custom.rules")
end
if is_file_exists(HOME .. "/.config/hypr-macshell/custom/keybinds.lua") then
    require("custom.keybinds")
end

-- nwg-displays support --
-- shared with the main session (stretchres owns these) --
if is_file_exists(HOME .. "/.config/hypr/workspaces.lua") then
    dofile(HOME .. "/.config/hypr/workspaces.lua")
end
if is_file_exists(HOME .. "/.config/hypr/monitors.lua") then
    dofile(HOME .. "/.config/hypr/monitors.lua")
end

-- stretchres state: must come after monitors.lua so its rules win --
-- dofile, not require: require caches, so a rewritten stretchres.lua
-- would be ignored on reload and the stale mode re-applied
if is_file_exists(HOME .. "/.config/hypr/stretchres.lua") then
    dofile(HOME .. "/.config/hypr/stretchres.lua")
end

-- Shell overrides --
require("hyprland.shellOverrides.main")

-- MacShell (replaces ii in this session) --
require("macshell")
