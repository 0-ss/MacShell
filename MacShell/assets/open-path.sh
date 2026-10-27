#!/bin/bash
# open-path.sh <path>: opens a file or folder from Spotlight.
#   folder      -> the file manager
#   *.AppImage  -> made executable if needed, then started (extract-and-run when FUSE is missing)
#   *.desktop   -> launched as an application
#   anything else -> the default app (xdg-open), then gio / the containing folder as fallbacks
p="$1"
note() { command -v notify-send >/dev/null 2>&1 && notify-send -a macshell "$1" "$2"; }
[ -n "$p" ] || exit 1
if [ ! -e "$p" ]; then note "Can't open" "$p no longer exists"; exit 1; fi
lower=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')

open_default() {
    if command -v xdg-open >/dev/null 2>&1 && xdg-open "$1" >/dev/null 2>&1; then return 0; fi
    if command -v gio >/dev/null 2>&1 && gio open "$1" >/dev/null 2>&1; then return 0; fi
    return 1
}

if [ -d "$p" ]; then
    open_default "$p" || note "Can't open folder" "$p"
    exit 0
fi

case "$lower" in
    *.appimage)
        if [ ! -x "$p" ] && ! chmod u+x "$p" 2>/dev/null; then note "Can't run AppImage" "$p is not executable and its permissions could not be changed"; exit 1; fi
        if ! command -v fusermount3 >/dev/null 2>&1 && ! command -v fusermount >/dev/null 2>&1; then export APPIMAGE_EXTRACT_AND_RUN=1; fi
        cd "$(dirname "$p")" 2>/dev/null
        setsid -f "$p" >/dev/null 2>&1 < /dev/null
        exit 0
        ;;
    *.desktop)
        if command -v gio >/dev/null 2>&1 && gio launch "$p" >/dev/null 2>&1; then exit 0; fi
        ;;
esac

if ! open_default "$p"; then
    d=$(dirname "$p")
    if open_default "$d"; then note "No app found for this file" "Opened its folder instead"
    else note "Can't open" "$p"; fi
fi
