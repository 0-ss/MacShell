#!/bin/sh
# Lock the session with MacLock (~/.config/quickshell/MacLock). Called by hypridle's lock_cmd.
# One locker at a time. If it crashes while locked, start it again: Hyprland keeps the session locked and
# misc:allow_session_lock_restore lets the new instance take over. After 5 crashes in a row, fall back to hyprlock.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/maclock.lock"
flock -n 9 || exit 0
pidof hyprlock >/dev/null && exit 0
# the lock plays the animated wallpaper with Qt Multimedia: decode it on the Intel iGPU (VA-API), never wake the NVIDIA dGPU
export QT_FFMPEG_DECODING_HW_DEVICE_TYPES=vaapi
# the desktop's animated wallpaper is hidden while locked: stop decoding it (MacLock plays its own copy)
"$HOME/.config/hypr-macshell/scripts/macshell-wallpause.sh" all pause
trap '"$HOME/.config/hypr-macshell/scripts/macshell-wallpause.sh" all resume' EXIT
# animations at each screen's own refresh rate (Qt otherwise paces them to the first, 60 Hz, screen)
export QSG_USE_SIMPLE_ANIMATION_DRIVER=1
# fewer malloc arenas: Qt runs ~50 threads, each would get its own heap arena (RAM that never comes back)
export MALLOC_ARENA_MAX=2
# A leftover MacLock that is no longer holding the session lock would keep this script from ever showing one
# (it answers the flock, then exits instantly). Clear it out before starting.
for p in $(pgrep -f 'qs -c MacLock' 2>/dev/null); do
    [ "$p" = "$$" ] && continue
    kill "$p" 2>/dev/null
done
sleep 0.1

n=0
while [ "$n" -lt 5 ]; do
    start=$(date +%s%N)
    qs -c MacLock
    rc=$?
    # exiting at once means the lock never engaged (another locker, no compositor support, a crash on startup):
    # that is the case where the screen silently stayed unlocked, so try again rather than return happy.
    ms=$(( ($(date +%s%N) - start) / 1000000 ))
    [ "$rc" = 0 ] && [ "$ms" -gt 1500 ] && exit 0
    n=$((n + 1))
    sleep 0.3
done
exec hyprlock
