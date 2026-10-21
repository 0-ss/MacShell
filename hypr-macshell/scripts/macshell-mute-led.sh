#!/bin/sh
# Laptop mute LEDs: they follow the sound card's own mute switches (kernel triggers audio-mute / audio-micmute),
# but muting in PipeWire never touches those, so the lights never came on. MacShell calls this whenever the
# output or the microphone is muted or unmuted, and the card's switches are set to match.
#   macshell-mute-led.sh speaker on|off      macshell-mute-led.sh mic on|off       (on = muted)
what="$1"; state="$2"
for c in /proc/asound/card[0-9]*; do
    n="${c##*card}"
    ctl=$(amixer -c "$n" scontrols 2>/dev/null) || continue
    if [ "$what" = speaker ]; then
        echo "$ctl" | grep -q "'Master'" || continue
        amixer -c "$n" -q sset Master "$([ "$state" = on ] && echo mute || echo unmute)" 2>/dev/null
    else
        # the internal microphone's capture switch: digital mics (Dmic0) first, else the analog Capture
        for m in Dmic0 Capture; do
            echo "$ctl" | grep -q "'$m'" || continue
            amixer -c "$n" -q sset "$m" "$([ "$state" = on ] && echo nocap || echo cap)" 2>/dev/null && break
        done
    fi
done
exit 0
