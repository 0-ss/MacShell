#!/bin/sh
# Brightness backend for MacBar.qml.
#   brightness.sh get       -> prints "<mode> <percent>"   (mode = bl | ddc | none)
#   brightness.sh set <1-100>
# Laptop panels use brightnessctl (sysfs backlight). If there is no backlight device (desktop PCs, external
# monitors) it falls back to ddcutil (DDC/CI, VCP feature 0x10) and sets every display ddcutil can see.
# ddcutil needs the i2c-dev kernel module and access to /dev/i2c-* (user in the "i2c" group, or a udev rule).

cache="${XDG_RUNTIME_DIR:-/tmp}/macshell-ddc-displays"

bl_line() { command -v brightnessctl >/dev/null 2>&1 && brightnessctl -m -c backlight 2>/dev/null | head -n1; }
has_bl() { [ -n "$(bl_line)" ]; }
has_ddc() { command -v ddcutil >/dev/null 2>&1; }

ddc_displays() {
    if [ -s "$cache" ]; then cat "$cache"; return; fi
    d=$(ddcutil detect --brief 2>/dev/null | sed -n 's/^Display \([0-9][0-9]*\).*/\1/p')
    [ -n "$d" ] && printf '%s\n' "$d" | tee "$cache"
}

case "$1" in
get)
    l=$(bl_line)
    if [ -n "$l" ]; then
        p=$(printf '%s' "$l" | cut -d, -f4 | tr -d '%')
        echo "bl ${p:-50}"
    elif has_ddc; then
        n=$(ddc_displays | head -n1)
        [ -z "$n" ] && { echo "none 50"; exit 0; }
        # terse output: "VCP 10 C <current> <max>"
        r=$(ddcutil --display "$n" getvcp 10 -t --sleep-multiplier .1 2>/dev/null | awk '$1=="VCP" && $3=="C" && $5>0 { printf "%d", $4*100/$5 }')
        [ -z "$r" ] && { rm -f "$cache"; echo "none 50"; exit 0; }
        echo "ddc $r"
    else
        echo "none 50"
    fi
    ;;
set)
    v=$(printf '%s' "$2" | tr -dc '0-9'); [ -z "$v" ] && exit 1
    [ "$v" -lt 1 ] && v=1; [ "$v" -gt 100 ] && v=100
    if has_bl; then
        brightnessctl -q -c backlight set "${v}%"
    elif has_ddc; then
        for n in $(ddc_displays); do
            ddcutil --display "$n" setvcp 10 "$v" --noverify --sleep-multiplier .1 >/dev/null 2>&1 &
        done
        wait
    fi
    ;;
*) echo "usage: $0 get | set <1-100>" >&2; exit 2 ;;
esac
