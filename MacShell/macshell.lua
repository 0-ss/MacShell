-- >>> MacShell module (added by install.sh) >>>
-- autostart (remove other bars / docks / notification daemons first).
-- install.sh adds this for you; macshell-start waits for the compositor and restarts the shell if it crashes.
hl.on("hyprland.start", function()
    hl.exec_cmd("awww-daemon")
    -- Install/update Hypridle's before_sleep_cmd hook (lid close is covered when it suspends).
    hl.exec_cmd("sh ~/.config/quickshell/MacLock/enable-sleep-lock.sh")
    hl.exec_cmd("sh ~/.local/bin/macshell-start")
end)
-- The Settings window floats and centres itself when it opens, so it needs no window rule.

-- keybinds (the name after -c is the config folder name, case-sensitive)
local qs = "qs -c MacShell ipc call "

hl.bind("SUPER + Z",          hl.dsp.exec_cmd(qs .. "settings toggle"))
hl.bind("SUPER + V",          hl.dsp.exec_cmd(qs .. "spotlight clipboard"))
hl.bind("SUPER + period",     hl.dsp.exec_cmd(qs .. "spotlight emoji"))
hl.bind("SUPER + Space",      hl.dsp.exec_cmd(qs .. "spotlight toggle"))
hl.bind("ALT + TAB",          hl.dsp.exec_cmd(qs .. "switcher next"))
hl.bind("CTRL + ALT + W",     hl.dsp.exec_cmd(qs .. "wallpapers toggle"))
hl.bind("PRINT",              hl.dsp.exec_cmd(qs .. "screenshot region"))

-- Hardware keys (laptop buttons too): volume, mute, brightness, media. MacShell handles them itself and shows its
-- on-screen display. If the shell is not running, wpctl / brightnessctl do the work instead.
-- "locked" keeps the keys working on the lock screen. Any earlier bind on the same key is dropped first, so a key never fires twice.
local function hw(action, fallback)
    return "sh -c '" .. qs .. "hardware " .. action .. " >/dev/null 2>&1 || " .. fallback .. "'"
end
local hwkeys = {
    { "XF86AudioRaiseVolume",  hw("volumeUp",       "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"),   true  },
    { "XF86AudioLowerVolume",  hw("volumeDown",     "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),        true  },
    { "XF86AudioMute",         hw("mute",           "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),       false },
    { "XF86AudioMicMute",      hw("micMute",        "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),     false },
    { "XF86MonBrightnessUp",   hw("brightnessUp",   "brightnessctl -q set 5%+"),                         true  },
    { "XF86MonBrightnessDown", hw("brightnessDown", "brightnessctl -q -n1 set 5%-"),                     true  },
    { "XF86KbdBrightnessUp",   "brightnessctl -q -d '*kbd_backlight*' set 10%+",                         true  },
    { "XF86KbdBrightnessDown", "brightnessctl -q -d '*kbd_backlight*' set 10%-",                         true  },
    { "XF86AudioPlay",         "playerctl play-pause",                                                   false },
    { "XF86AudioPause",        "playerctl pause",                                                        false },
    { "XF86AudioNext",         "playerctl next",                                                         false },
    { "XF86AudioPrev",         "playerctl previous",                                                     false },
}
for _, k in ipairs(hwkeys) do
    pcall(hl.unbind, k[1])
    hl.bind(k[1], hl.dsp.exec_cmd(k[2]), { locked = true, repeating = k[3] })
end

-- MacLock (lock screen)
hl.bind("SUPER + L",          hl.dsp.exec_cmd("sh ~/.config/quickshell/MacLock/lock-via-ipc.sh"))
-- <<< MacShell module <<<
