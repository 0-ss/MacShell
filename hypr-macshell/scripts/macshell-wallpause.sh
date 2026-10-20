#!/bin/sh
# Pause / resume the animated wallpaper on one monitor (or all) through mpv's IPC socket.
#   macshell-wallpause.sh <output|all> <pause|resume>
run="${XDG_RUNTIME_DIR:-/tmp}"; v=$([ "$2" = pause ] && echo true || echo false)
for s in "$run"/macshell-mpv-*.sock; do
    [ -S "$s" ] || continue
    case "$1" in all) ;; *) [ "$s" = "$run/macshell-mpv-$1.sock" ] || continue ;; esac
    printf '{"command":["set_property","pause",%s]}\n' "$v" | timeout 1 nc -U -N "$s" >/dev/null 2>&1
done
