#!/bin/sh
# The pointer: Apple's macOS cursors (black or white) at the size chosen in Settings → Mouse.
#   macshell-cursor.sh                 apply what Settings saved (~/.config/macdock/settings.json)
#   macshell-cursor.sh <theme> <size>  apply these
cfg="$HOME/.config/macdock/settings.json"
theme="${1:-$(jq -r '.cursorTheme // "macOS"' "$cfg" 2>/dev/null)}"
size="${2:-$(jq -r '.cursorSize // 24' "$cfg" 2>/dev/null)}"
[ -n "$theme" ] && [ "$theme" != null ] || theme=macOS
[ -n "$size" ] && [ "$size" != null ] || size=24
# fall back to whatever is installed if the macOS set isn't (./install.sh --icons fetches it)
for d in "$HOME/.local/share/icons" "$HOME/.icons" /usr/share/icons; do [ -d "$d/$theme/cursors" ] && found=1; done
[ -n "$found" ] || theme=Bibata-Modern-Classic
hyprctl setcursor "$theme" "$size" >/dev/null 2>&1
