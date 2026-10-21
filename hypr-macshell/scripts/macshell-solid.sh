#!/bin/sh
# Opaque material / Game Mode: every window fully opaque, no blur anywhere — and back again.
#   macshell-solid.sh on | off
# on : remembers your window opacity and blur (from your Hyprland config), then sets windows to 100 % and blur off.
# off: puts back exactly what was remembered. Safe to call twice.
state="${XDG_RUNTIME_DIR:-/tmp}/macshell-solid.state"
opt() { hyprctl getoption "$1" 2>/dev/null | awk 'NR==1 {print $2}'; }
lua_bool() { case "$1" in 1|true) echo true ;; *) echo false ;; esac; }

case "$1" in
on)
    if [ ! -f "$state" ]; then
        {
            echo "active=$(opt decoration:active_opacity)"
            echo "inactive=$(opt decoration:inactive_opacity)"
            echo "fullscreen=$(opt decoration:fullscreen_opacity)"
            # Game Mode may already have switched blur off: what it remembered is the real setting
            g="${XDG_RUNTIME_DIR:-/tmp}/macshell-gaming.state"
            if [ -f "$g" ]; then echo "blur=$(sed -n 's/^blur=//p' "$g")"; else echo "blur=$(opt decoration:blur:enabled)"; fi
        } > "$state"
    fi
    hyprctl eval 'hl.config({ decoration = { active_opacity = 1.0, inactive_opacity = 1.0, fullscreen_opacity = 1.0, blur = { enabled = false } } })' >/dev/null 2>&1
    ;;
off)
    [ -f "$state" ] || exit 0
    . "$state"
    hyprctl eval "hl.config({ decoration = { active_opacity = ${active:-1.0}, inactive_opacity = ${inactive:-1.0}, fullscreen_opacity = ${fullscreen:-1.0}, blur = { enabled = $(lua_bool "${blur:-1}") } } })" >/dev/null 2>&1
    rm -f "$state"
    ;;
*)
    echo "usage: $0 on|off" >&2; exit 2 ;;
esac
