#!/bin/sh
# Two lines for the status icons: the Wi-Fi level (-1 unknown/off, 0 off, 1..100 signal) and "eth" when a cable is connected.
if [ "$(nmcli radio wifi 2>/dev/null)" = enabled ]; then
    s=$(nmcli -t -f ACTIVE,SIGNAL dev wifi 2>/dev/null | grep '^yes' | head -n1 | cut -d: -f2)
    [ -n "$s" ] && printf '%s' "$s" || printf 0
else
    printf -- -1
fi
echo
nmcli -t -f TYPE,STATE dev 2>/dev/null | grep -q '^ethernet:connected$' && echo eth || echo -
