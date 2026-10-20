-- MacShell session overrides (loaded last from hyprland.lua).
-- ii's shell binds point at `quickshell:*` globals / `qs -c ii` that don't exist in
-- this session; Hyprland fires every bind on a key, so unbind before rebinding.

local mac = "qs -c MacShell ipc call"

for _, key in ipairs({
    "SUPER + SUPER_L", "SUPER + SUPER_R", "SUPER_L", "SUPER_R",
    "SUPER + Tab", "SUPER + V", "SUPER + Period", "SUPER + A", "SUPER + ALT + A",
    "SUPER + B", "SUPER + O", "SUPER + N", "SUPER + Slash", "SUPER + K", "SUPER + M",
    "SUPER + G", "CTRL + ALT + Delete", "SUPER + J", "SHIFT + SUPER + ALT + Slash",
    "XF86MonBrightnessUp", "XF86MonBrightnessDown",
    "CTRL + SUPER + T", "CTRL + SUPER + ALT + T", "CTRL + SUPER + SHIFT + D",
    "CTRL + SUPER + R", "CTRL + SUPER + P", "SUPER + SHIFT + S", "SUPER + SHIFT + A",
}) do
    -- Hyprland keeps every binding made for a key and fires them all, and one hl.unbind drops only one of
    -- them. ii binds some of these twice (a shell global plus a fuzzel fallback), so SUPER + V used to open
    -- our Clipboard and a fuzzel menu at the same time, and whichever grabbed the keyboard last won.
    for _ = 1, 4 do
        hl.unbind(key)
    end
end

-- MacShell
hl.bind("SUPER + Space", hl.dsp.exec_cmd(mac .. " spotlight toggle"), { description = "MacShell: Spotlight" })
hl.bind("SUPER + SUPER_L", hl.dsp.exec_cmd(mac .. " spotlight toggle"), { release = true })
hl.bind("SUPER + V", hl.dsp.exec_cmd(mac .. " spotlight clipboard"), { description = "MacShell: Clipboard history" })
hl.bind("SUPER + Period", hl.dsp.exec_cmd(mac .. " spotlight emoji"), { description = "MacShell: Emoji" })
hl.bind("ALT + Tab", hl.dsp.exec_cmd(mac .. " switcher next"), { description = "MacShell: Window switcher" })
hl.bind("ALT + SHIFT + Tab", hl.dsp.exec_cmd(mac .. " switcher prev"))
hl.bind("ALT_L", hl.dsp.exec_cmd(mac .. " switcher commit"), { ignore_mods = true, transparent = true, release = true })
hl.bind("CTRL + ALT + W", hl.dsp.exec_cmd(mac .. " wallpapers toggle"), { description = "MacShell: Wallpapers" })
hl.bind("CTRL + SUPER + T", hl.dsp.exec_cmd(mac .. " wallpapers toggle"))
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd(mac .. " screenshot region"), { description = "MacShell: Screenshot region" })
hl.bind("CTRL + SUPER + R", hl.dsp.exec_cmd("pkill -x qs"), { description = "MacShell: Restart (autostart loop relaunches it)" })
hl.bind("CTRL + ALT + Delete", hl.dsp.exec_cmd("pidof wlogout || wlogout -p layer-shell"))
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl s 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 5%-"), { locked = true, repeating = true })

-- Glass surfaces
hl.layer_rule({ name = "macdock",  match = { namespace = "macdock"  }, blur = true, ignore_alpha = 0.2,  no_anim = true })
-- Spotlight draws its own Liquid Glass: compositor blur behind it stayed solid while Spotlight faded (the shapes never faded out)
hl.layer_rule({ name = "macspot",  match = { namespace = "macspot"  }, blur = false, no_anim = true })
hl.layer_rule({ name = "macbarbg", match = { namespace = "macbarbg" }, blur = true, ignore_alpha = 0.05, no_anim = true })
hl.layer_rule({ name = "macshot",  match = { namespace = "macshot"  }, no_anim = true })
-- the welcome screen sits above the bar and the Dock
hl.layer_rule({ name = "macwelcome", match = { namespace = "macwelcome" }, order = 10, no_anim = true })
hl.window_rule({ match = { title = "^macshell Settings$" }, float = true })
hl.window_rule({ match = { class = "^org\\.quickshell$", title = "^Clock$" }, float = true, size = "780 540", center = true })
hl.window_rule({ match = { class = "^org\\.quickshell$", title = "^App Store$" }, float = true, size = "1080 720", center = true })
hl.window_rule({ match = { class = "^org\\.quickshell$", title = "^Photos$" }, float = true, size = "1100 740", center = true })
hl.window_rule({ match = { class = "^org\\.quickshell$", title = "^Finder$" }, float = true, size = "1020 660", center = true })
hl.window_rule({ match = { class = "^org\\.quickshell$", title = "^AirDrop$" }, float = true, size = "620 500", center = true })
hl.window_rule({ match = { class = "^org\\.quickshell$", title = "^Preview$" }, float = true, size = "960 660", center = true })
hl.window_rule({ match = { class = "^org\\.quickshell$", title = "^Player$" }, float = true, size = "900 540", center = true })

-- Settings → Desktop & Dock → "Open windows floating": MacShell writes this file
pcall(dofile, os.getenv("HOME") .. "/.config/macshell/windows.lua")

-- Settings → Keyboard → Keyboard Shortcuts: MacShell writes this file (it overrides the binds above)
pcall(dofile, os.getenv("HOME") .. "/.config/macshell/keybinds.lua")
