#!/bin/sh
# MacShell session wallpaper: ii drew its own background, MacShell relies on a daemon.
# Applies MacShell's remembered wallpaperPath (set by its Ctrl+Alt+W picker),
# falling back to the current ii wallpaper.
cfg="$HOME/.config/macdock/settings.json"
p=$(jq -r '.wallpaperPath // empty' "$cfg" 2>/dev/null)
[ -f "$p" ] || p=$(jq -r '.background.wallpaperPath // empty' "$HOME/.config/illogical-impulse/config.json" 2>/dev/null)
pgrep -x awww-daemon >/dev/null || { setsid awww-daemon >/dev/null 2>&1 & }
for i in $(seq 30); do awww query >/dev/null 2>&1 && break; sleep 0.2; done
[ -f "$p" ] && awww img "$p" --transition-type none
# animated wallpaper (video) set from MacShell Settings → Wallpaper: start it again on top of the still frame
"$HOME/.config/hypr-macshell/scripts/macshell-setwall.sh" --restore >/dev/null 2>&1
