#!/bin/sh
# Wallpaper appearance for light/dark wallpaper pairs (macOS: Automatic / Light / Dark / Dynamic).
#   macshell-dynwall.sh <light> <dark> <light|dark|dynamic> [sunriseMin sunsetMin]
# dynamic: light during the day, dark at night, and around sunrise / sunset it steps through blended images
# (light → dark over ~75 min), like macOS's time-of-day dynamic wallpapers. Applies with a fade only when the
# image actually changes, and prints the image in use (the Liquid Glass refracts it).
light="$1"; dark="$2"; mode="$3"; rise="${4:-390}"; set_="${5:-1110}"
cache="$HOME/.cache/macshell/dynamic"; mkdir -p "$cache"
[ -f "$light" ] && [ -f "$dark" ] || exit 1

blend() {   # $1 = 0..100 (% dark)
    k=$(printf '%s|%s' "$light" "$dark" | md5sum | cut -c1-12)
    out="$cache/$k-$1.jpg"
    [ -s "$out" ] || nice -n 15 magick "$light" "$dark" -resize 2560x\> -compose blend -define compose:args="$1" -composite -quality 92 "$out" 2>/dev/null \
        || nice -n 15 magick "$dark" "$light" -resize 2560x\> -compose dissolve -define compose:args="$1" -composite -quality 92 "$out"
    printf '%s' "$out"
}

case "$mode" in
light) img="$light" ;;
dark)  img="$dark" ;;
dynamic)
    now=$(( $(date +%-H) * 60 + $(date +%-M) ))
    ramp=75
    # 0 = day, 100 = night, ramping before sunset and after sunrise
    if [ "$now" -ge $((set_ - ramp)) ] && [ "$now" -lt "$set_" ]; then f=$(( (now - (set_ - ramp)) * 100 / ramp ))
    elif [ "$now" -ge "$rise" ] && [ "$now" -lt $((rise + ramp)) ]; then f=$(( 100 - (now - rise) * 100 / ramp ))
    elif [ "$now" -ge $((rise + ramp)) ] && [ "$now" -lt $((set_ - ramp)) ]; then f=0
    else f=100; fi
    step=$(( (f + 12) / 25 * 25 ))          # 0 25 50 75 100
    case $step in 0) img="$light" ;; 100) img="$dark" ;; *) img=$(blend $step) ;; esac ;;
*) exit 2 ;;
esac

cur=$(awww query 2>/dev/null | sed -n 's/.*image: //p' | head -n1)
if [ "$cur" != "$img" ]; then
    # a video wallpaper was playing: drop its state first (its supervisor then stops restarting it), then stop it for real
    if [ -f "$HOME/.config/macshell/wallpaper-video" ] || pgrep -x mpvpaper >/dev/null; then
        rm -f "$HOME/.config/macshell/wallpaper-video" "$HOME/.config/macshell/wallpaper-video-play" "$HOME/.config/macshell/wallpaper-video-glass"
        pkill -CONT -x mpvpaper 2>/dev/null; pkill -TERM -x mpvpaper 2>/dev/null; sleep 0.4; pkill -KILL -x mpvpaper 2>/dev/null
    fi
    awww img "$img" --transition-type fade --transition-duration 1.5 >/dev/null 2>&1
fi
printf '%s\n' "$img"
