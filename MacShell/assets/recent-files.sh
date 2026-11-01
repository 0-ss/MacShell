#!/bin/bash
# recent-files.sh [N]: prints the N most recent files / folders of the user, newest first, one per line:
#   <epoch>\t<f|d>\t<absolute path>
# Sources: recently used files of GTK/Qt apps (recently-used.xbel) + whatever changed lately in Downloads, Documents,
# Desktop, Pictures, Videos, Music and the top of $HOME. "Changed" is the newer of mtime / ctime, so a file that was just
# downloaded or moved there counts as recent even when it carries an old modification date.
N="${1:-40}"
H="${HOME:-/}"
dirs=()
add() { [ -n "$1" ] && [ -d "$1" ] && [ "$1" != "$H" ] && [ "$1" != "$H/" ] && dirs+=("$1"); }
if command -v xdg-user-dir >/dev/null 2>&1; then
    for k in DOWNLOAD DOCUMENTS DESKTOP PICTURES VIDEOS MUSIC; do add "$(xdg-user-dir "$k" 2>/dev/null)"; done
fi
for d in Downloads Documents Desktop Pictures Videos Music Applications; do add "$H/$d"; done
mapfile -t dirs < <(printf '%s\n' "${dirs[@]}" | awk 'NF && !s[$0]++')

PRUNE=( \( -name '.*' -o -name node_modules -o -name __pycache__ \) -prune -o )
{
    for d in "${dirs[@]}"; do
        find "$d" -maxdepth 3 "${PRUNE[@]}" -type f -printf '%T@\t%C@\tf\t%p\n' 2>/dev/null
        find "$d" -mindepth 1 -maxdepth 2 "${PRUNE[@]}" -type d -printf '%T@\t%C@\td\t%p\n' 2>/dev/null
    done
    find "$H" -mindepth 1 -maxdepth 1 "${PRUNE[@]}" \( -type f -o -type d \) -printf '%T@\t%C@\t%y\t%p\n' 2>/dev/null

    xbel="${XDG_DATA_HOME:-$H/.local/share}/recently-used.xbel"
    if [ -r "$xbel" ]; then
        grep -o '<bookmark href="file://[^"]*"[^>]*>' "$xbel" 2>/dev/null | tail -n 120 | while IFS= read -r line; do
            href=${line#*href=\"}; href=${href%%\"*}
            p=${href#file://}
            p=$(printf '%b' "${p//%/\\x}")
            [ -e "$p" ] || continue
            ts=""
            for key in visited modified added; do
                if [[ $line == *" $key=\""* ]]; then ts=${line#* $key=\"}; ts=${ts%%\"*}; break; fi
            done
            e=$(date -d "$ts" +%s 2>/dev/null) || continue
            if [ -d "$p" ]; then k=d; else k=f; fi
            printf '%s\t%s\t%s\t%s\n' "$e" "$e" "$k" "$p"
        done
    fi
} | awk -F'\t' '
    $3 != "f" && $3 != "d" { next }
    { t = ($1 + 0 > $2 + 0) ? $1 : $2 }
    $4 ~ /\.(part|crdownload|tmp|swp)$/ { next }
    $4 ~ /\/(\.cache|\.local\/share\/Trash)\// { next }
    { printf "%d\t%s\t%s\n", t, $3, $4 }
' | sort -t "$(printf '\t')" -k1,1nr | awk -F'\t' -v n="$N" '!seen[$3]++ { print; if (++c >= n) exit }'
