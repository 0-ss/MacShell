#!/bin/sh
# MacShell Game Mode: frees the GPU/CPU for games, and puts everything back afterwards.
#   macshell-gaming.sh on | off | status
# on : saves the current Hyprland blur / shadow / animation settings and the power profile, then turns blur,
#      shadows and animations off, pauses the animated wallpaper (mpvpaper gets SIGSTOP: no decoding at all) and
#      switches to the performance power profile.
# off: restores exactly what was saved. Safe to call twice; "off" without a saved state does nothing.
# MacShell itself drops Liquid Glass to plain blur and stops its live window captures while Game Mode is on.
state="${XDG_RUNTIME_DIR:-/tmp}/macshell-gaming.state"

opt() { hyprctl getoption "$1" 2>/dev/null | awk 'NR==1 {print $2}'; }
lua_bool() { case "$1" in 1|true) echo true ;; *) echo false ;; esac; }

case "$1" in
on)
    if [ ! -f "$state" ]; then
        {
            echo "blur=$(opt decoration:blur:enabled)"
            echo "shadow=$(opt decoration:shadow:enabled)"
            echo "anim=$(opt animations:enabled)"
            echo "profile=$(powerprofilesctl get 2>/dev/null)"
        } > "$state"
    fi
    hyprctl eval 'hl.config({ decoration = { blur = { enabled = false }, shadow = { enabled = false } }, animations = { enabled = false } })' >/dev/null 2>&1
    pkill -STOP -x mpvpaper 2>/dev/null
    powerprofilesctl set performance 2>/dev/null
    ;;
off)
    [ -f "$state" ] || exit 0
    . "$state"
    hyprctl eval "hl.config({ decoration = { blur = { enabled = $(lua_bool "${blur:-1}") }, shadow = { enabled = $(lua_bool "${shadow:-1}") } }, animations = { enabled = $(lua_bool "${anim:-1}") } })" >/dev/null 2>&1
    pkill -CONT -x mpvpaper 2>/dev/null
    [ -n "$profile" ] && powerprofilesctl set "$profile" 2>/dev/null
    rm -f "$state"
    ;;
status)
    [ -f "$state" ] && echo on || echo off
    ;;
*)
    echo "usage: $0 on|off|status" >&2; exit 2 ;;
esac
