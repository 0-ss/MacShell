#!/bin/sh
# macshell-ap — the one privileged step Internet Sharing needs.
#
# Most Wi-Fi chips can run a client and an access point at the same time, but the access point has
# to live on its own virtual interface, and creating one needs root. That is all this script does:
# add or remove a single __ap interface. It takes no other arguments and touches nothing else, so it
# is safe to allow without a password (install.sh offers to add a sudoers line for exactly this file).
#
#   macshell-ap check   does this radio allow a client and an AP at once, and on how many channels
#   macshell-ap add     create the AP interface (prints its name)
#   macshell-ap del     remove it
set -eu

IFACE=macap0

base_iface() {
    iw dev 2>/dev/null | awk '/^\tInterface /{i=$2} /^\t\ttype managed$/{print i; exit}'
}

case "${1:-}" in
check)
    # "AP" inside a combination line that also allows a managed interface
    if iw list 2>/dev/null | awk '
            /valid interface combinations/ {inblock=1; next}
            inblock && /^\t\t \*/ {line=$0; getline more; line=line more}
            inblock && line ~ /managed/ && line ~ /AP/ {print "yes"; found=1; exit}
            inblock && /^\t[A-Za-z]/ {exit}
            END {if (!found) print "no"}' | grep -q yes; then
        echo yes
    else
        echo no
    fi
    ;;
add)
    b=$(base_iface)
    [ -n "$b" ] || { echo "no managed Wi-Fi interface" >&2; exit 1; }
    if ! iw dev "$IFACE" info >/dev/null 2>&1; then
        iw dev "$b" interface add "$IFACE" type __ap
    fi
    ip link set "$IFACE" up >/dev/null 2>&1 || true
    echo "$IFACE"
    ;;
del)
    iw dev "$IFACE" del >/dev/null 2>&1 || true
    ;;
*)
    echo "usage: macshell-ap check|add|del" >&2
    exit 2
    ;;
esac
