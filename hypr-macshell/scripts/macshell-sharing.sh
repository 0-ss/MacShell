#!/bin/sh
# Internet Sharing, one way for the whole shell (Settings → Sharing and the Control Center tile both run this).
#
#   macshell-sharing.sh start <name> <password> <band a|bg>     share this computer's connection over Wi-Fi
#   macshell-sharing.sh stop [network-to-rejoin]
#   macshell-sharing.sh mode                                      shared | takeover
#
# Shared: the access point gets its own virtual interface (the macshell-ap root helper, ./install.sh hotspot), so
# the Wi-Fi connection you are on stays up; one radio means one channel, so it sits on the channel you're on.
# Takeover: no helper or the adapter can't do both, so the adapter becomes the access point while sharing is on.
helper=/usr/local/bin/macshell-ap

mode() {
    if [ -x "$helper" ] && [ "$("$helper" check 2>/dev/null)" = yes ]; then echo shared; else echo takeover; fi
}

case "$1" in
mode) mode ;;
start)
    ssid="${2:-${USER:-MacShell}'s MacShell}"; pass="$3"; band="${4:-bg}"
    [ ${#pass} -ge 8 ] || pass=macshell1
    m=$(mode)
    nmcli con delete MacShell-Hotspot >/dev/null 2>&1 || true
    wifi=$(nmcli -t -f DEVICE,TYPE dev | grep ':wifi$' | cut -d: -f1 | head -1)
    [ -n "$wifi" ] || { echo 'no Wi-Fi adapter'; exit 1; }
    ch=''
    if [ "$m" = shared ]; then
        dev=$(sudo -n "$helper" add 2>/dev/null || pkexec "$helper" add) || { echo 'could not create the AP interface'; exit 1; }
        ch=$(iw dev "$wifi" info 2>/dev/null | awk '/channel/{print $2; exit}')
        if [ -n "$ch" ] && [ "$ch" -gt 14 ] 2>/dev/null; then band=a; elif [ -n "$ch" ]; then band=bg; fi
    else
        dev="$wifi"
    fi
    nmcli con add type wifi ifname "$dev" con-name MacShell-Hotspot autoconnect no ssid "$ssid" >/dev/null || exit 1
    nmcli con modify MacShell-Hotspot 802-11-wireless.mode ap 802-11-wireless.band "$band" \
        ipv4.method shared ipv6.method ignore \
        wifi-sec.key-mgmt wpa-psk wifi-sec.proto rsn wifi-sec.pairwise ccmp wifi-sec.group ccmp wifi-sec.psk "$pass" >/dev/null || exit 1
    [ -n "$ch" ] && nmcli con modify MacShell-Hotspot 802-11-wireless.channel "$ch" >/dev/null
    nmcli con up MacShell-Hotspot 2>&1 | tail -1
    ;;
stop)
    m=$(mode)
    nmcli con down MacShell-Hotspot >/dev/null 2>&1
    nmcli con delete MacShell-Hotspot >/dev/null 2>&1
    sudo -n "$helper" del >/dev/null 2>&1 || true
    # only needed when sharing had taken the adapter over; a no-op otherwise
    [ -n "$2" ] && [ "$m" != shared ] && nmcli --wait 20 con up "$2" >/dev/null 2>&1
    nmcli dev wifi rescan >/dev/null 2>&1
    exit 0
    ;;
*) echo "usage: $0 start <name> <password> <band> | stop [network] | mode" >&2; exit 2 ;;
esac
