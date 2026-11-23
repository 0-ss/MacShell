#!/usr/bin/env bash
# Keeps files that are intentionally byte-identical copies of a MacShell source in sync.
# Usage: sync-shared.sh --check | --apply
set -euo pipefail

mode="${1:-}"
case "$mode" in
    --check | --apply) ;;
    *) echo "usage: ${0##*/} --check | --apply" >&2; exit 2 ;;
esac
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# source -> mirror(s)
pairs=(
    "MacShell/lang/es.js MacInstaller/lang/es.js"
    "MacShell/lang/ru.js MacInstaller/lang/ru.js"
    "MacShell/I18n.js MacInstaller/I18n.js"
    "MacShell/Fonts.js MacInstaller/Fonts.js"
    "MacShell/CornerBorder.qml MacInstaller/CornerBorder.qml"
    "MacShell/FeatherBlur.qml MacInstaller/FeatherBlur.qml"
    "MacShell/TLGlyph.qml MacInstaller/TLGlyph.qml"
    "MacShell/liquidglass.frag MacInstaller/liquidglass.frag"
    "MacShell/liquidglass.frag.qsb MacInstaller/liquidglass.frag.qsb"
    "MacShell/ClockGlyph.qml MacLock/ClockGlyph.qml"
    "MacShell/MorphText.qml MacLock/MorphText.qml"
    "MacShell/burn.frag MacLock/burn.frag"
    "MacShell/burn.frag.qsb MacLock/burn.frag.qsb"
    "MacShell/contourglow.frag MacLock/contourglow.frag"
    "MacShell/contourglow.frag.qsb MacLock/contourglow.frag.qsb"
    "MacShell/fade.frag MacLock/fade.frag"
    "MacShell/fade.frag.qsb MacLock/fade.frag.qsb"
    "MacShell/genius-lyrics.py MacLock/genius-lyrics.py"
    "MacShell/lyrics_fetcher.py MacLock/lyrics_fetcher.py"
    "MacShell/assets/fonts/OpenRunde-Regular.otf MacInstaller/assets/fonts/OpenRunde-Regular.otf"
    "MacShell/assets/fonts/OpenRunde-Regular.otf MacLock/fonts/OpenRunde-Regular.otf"
    "MacShell/assets/fonts/OpenRunde-Semibold.otf MacInstaller/assets/fonts/OpenRunde-Semibold.otf"
    "MacShell/assets/fonts/OpenRunde-Semibold.otf MacLock/fonts/OpenRunde-Semibold.otf"
)

drift=0
for pair in "${pairs[@]}"; do
    read -r src dst <<<"$pair"
    if [[ ! -f $src ]]; then
        echo "missing source: $src" >&2
        drift=1
    elif [[ ! -f $dst ]] || ! cmp -s "$src" "$dst"; then
        if [[ $mode == --apply ]]; then
            cp "$src" "$dst"
            echo "synced: $dst"
        else
            echo "drift: $dst differs from $src" >&2
            drift=1
        fi
    fi
done
exit "$drift"
