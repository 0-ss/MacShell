#!/bin/sh
# MacShell Game Mode: frees the GPU/CPU for games, and puts everything back afterwards.
#   macshell-gaming.sh on | off | status
# on : saves the current Hyprland blur / shadow / animation settings and the power profile, then turns blur,
#      shadows and animations off, pauses the animated wallpaper (mpvpaper gets SIGSTOP: no decoding at all) and
#      switches to the performance power profile.
# off: restores exactly what was saved. Safe to call twice; "off" without a saved state does nothing.
# MacShell itself drops Liquid Glass to plain blur and stops its live window captures while Game Mode is on.
if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "$XDG_RUNTIME_DIR" ]; then
    state_dir="$XDG_RUNTIME_DIR"
else
    state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/macshell"
    mkdir -p "$state_dir" && chmod 700 "$state_dir" || exit 1
fi
state="$state_dir/macshell-gaming.state"

opt() { hyprctl getoption "$1" 2>/dev/null | awk 'NR==1 {print $2}'; }
lua_bool() { case "$1" in 1|true) echo true ;; *) echo false ;; esac; }

case "$1" in
on)
    if [ ! -f "$state" ]; then
        tmp=$(mktemp "$state_dir/macshell-gaming.XXXXXX") || exit 1
        {
            echo "blur=$(opt decoration:blur:enabled)"
            echo "shadow=$(opt decoration:shadow:enabled)"
            echo "anim=$(opt animations:enabled)"
            echo "profile=$(powerprofilesctl get 2>/dev/null | tr -cd 'a-z-')"
        } > "$tmp" && mv -f "$tmp" "$state" || { rm -f "$tmp"; exit 1; }
    fi
    hyprctl eval 'hl.config({ decoration = { blur = { enabled = false }, shadow = { enabled = false } }, animations = { enabled = false } })' >/dev/null 2>&1
    pkill -STOP -x mpvpaper 2>/dev/null
    powerprofilesctl set performance 2>/dev/null
    ;;
off)
    [ -f "$state" ] || exit 0
    blur=""; shadow=""; anim=""; profile=""
    # parse key=value lines instead of sourcing the file, so nothing in it is ever executed
    while IFS='=' read -r k v; do
        case "$k" in
            blur) blur=$v ;;
            shadow) shadow=$v ;;
            anim) anim=$v ;;
            profile) profile=$v ;;
        esac
    done < "$state"
    hyprctl eval "hl.config({ decoration = { blur = { enabled = $(lua_bool "${blur:-1}") }, shadow = { enabled = $(lua_bool "${shadow:-1}") } }, animations = { enabled = $(lua_bool "${anim:-1}") } })" >/dev/null 2>&1
    pkill -CONT -x mpvpaper 2>/dev/null
    case "$profile" in power-saver|balanced|performance) powerprofilesctl set "$profile" 2>/dev/null ;; esac
    rm -f "$state"
    ;;
status)
    [ -f "$state" ] && echo on || echo off
    ;;
*)
    echo "usage: $0 on|off|status" >&2; exit 2 ;;
esac
