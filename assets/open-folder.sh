#!/bin/bash
# open-folder.sh <dir>: opens a folder in a GRAPHICAL file manager.
#   1. the system default for inode/directory, unless it is a terminal program (ranger, yazi, nnn, ... -> Terminal=true)
#   2. any other registered FILE MANAGER (Categories=FileManager) that is not a terminal program
#   3. well-known file managers found on PATH
#   4. xdg-open, as the last resort
p="$1"
[ -d "$p" ] || exit 1

data_dirs() {
    printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}"
    local IFS=:
    for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do printf '%s\n' "$d"; done
}
desktop_file() {   # name.desktop -> full path
    local n="$1" d
    while IFS= read -r d; do [ -f "$d/applications/$n" ] && { printf '%s\n' "$d/applications/$n"; return 0; }; done < <(data_dirs)
    return 1
}
# a terminal program, even one that is not marked Terminal=true: kitty-open.desktop (kitty) also claims inode/directory, and
# opens a folder as a shell prompt in that folder
is_term() {
    grep -qiE '^Terminal=true' "$1" 2>/dev/null && return 0
    grep -qiE '^Categories=.*TerminalEmulator' "$1" 2>/dev/null && return 0
    grep -iE '^Exec=' "$1" 2>/dev/null | head -n1 | grep -qiE '(^|[ /=])(kitty|alacritty|foot|footclient|wezterm|wezterm-gui|ghostty|konsole|xterm|urxvt|rxvt|terminator|tilix|ptyxis|gnome-terminal|xfce4-terminal|st|ranger|yazi|nnn|lf|mc|vifm)( |$)' && return 0
    return 1
}
is_gui() { ! is_term "$1"; }
is_fm() { is_gui "$1" && grep -qiE '^Categories=.*FileManager' "$1" 2>/dev/null; }
launch() {         # desktop file path -> opens $p with it
    local f="$1" n
    n=$(basename "$f")
    if command -v gio >/dev/null 2>&1 && gio launch "$f" "$p" >/dev/null 2>&1; then return 0; fi
    if command -v gtk-launch >/dev/null 2>&1 && gtk-launch "${n%.desktop}" "$p" >/dev/null 2>&1; then return 0; fi
    return 1
}

# 1. the system default (kitty-open and other terminal handlers are skipped)
def=$(xdg-mime query default inode/directory 2>/dev/null)
if [ -n "$def" ] && f=$(desktop_file "$def") && is_gui "$f" && launch "$f"; then exit 0; fi

# 2. other registered folder handlers
while IFS= read -r d; do
    [ -f "$d/applications/mimeinfo.cache" ] || continue
    line=$(grep -m1 '^inode/directory=' "$d/applications/mimeinfo.cache")
    IFS=';' read -ra apps <<< "${line#inode/directory=}"
    for a in "${apps[@]}"; do
        [ -n "$a" ] && f=$(desktop_file "$a") && is_fm "$f" && launch "$f" && exit 0
    done
done < <(data_dirs)

# 3. well-known file managers
for fm in dolphin nautilus thunar nemo pcmanfm-qt pcmanfm caja spacefm; do
    if command -v "$fm" >/dev/null 2>&1; then setsid -f "$fm" "$p" >/dev/null 2>&1 < /dev/null; exit 0; fi
done

# 4. last resort
exec xdg-open "$p"
