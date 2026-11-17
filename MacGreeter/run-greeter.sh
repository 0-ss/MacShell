#!/bin/sh
# Started by the greeter's Hyprland: runs the login screen, then ends that Hyprland.
SYS="$(cd "$(dirname "$0")" && pwd)"
STATE="${MACGREETER_STATE:-/var/lib/macshell-greeter}"
LOG="$STATE/state/greeter.log"
export QT_QPA_PLATFORM=wayland
export MACGREETER_STATE="$STATE"
# your own graphics settings for the greeter (for example: export QSG_RHI_BACKEND=opengl) can go in $STATE/env
[ -r "$STATE/env" ] && . "$STATE/env"
[ "$(wc -c < "$LOG" 2>/dev/null | tr -d ' ')" -gt 524288 ] 2>/dev/null && mv -f "$LOG" "$LOG.old" 2>/dev/null
qs -p "$SYS" >>"$LOG" 2>&1
hyprctl dispatch exit >/dev/null 2>&1 || hyprctl dispatch 'hl.dsp.exit()' >/dev/null 2>&1
