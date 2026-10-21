#!/bin/sh
# MacShell session wallpaper: starts awww and shows MacShell's remembered wallpaper (Settings → Wallpaper /
# Ctrl+Alt+W), or the macOS Golden Gate picture on a fresh install.
cfg="$HOME/.config/macdock/settings.json"
p=$(jq -r '.wallpaperPath // empty' "$cfg" 2>/dev/null)
[ -f "$p" ] || p=$(jq -r '.wallpaperPath // empty' "$HOME/.config/macbar/settings.json" 2>/dev/null)
[ -f "$p" ] || p="$HOME/Pictures/Wallpapers/macos-27-GoldenGate-Dark.png"
pgrep -x awww-daemon >/dev/null || { setsid awww-daemon >/dev/null 2>&1 & }
for i in $(seq 30); do awww query >/dev/null 2>&1 && break; sleep 0.2; done
[ -f "$p" ] && awww img "$p" --transition-type none
# animated wallpaper (video) set from MacShell Settings → Wallpaper: start it again on top of the still frame
"$HOME/.config/hypr-macshell/scripts/macshell-setwall.sh" --restore >/dev/null 2>&1
