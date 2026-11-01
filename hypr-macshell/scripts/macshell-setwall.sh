#!/bin/sh
# Set the MacShell wallpaper: a picture (awww) or an animated one (video → mpvpaper on every monitor).
#   macshell-setwall.sh <file>        apply it
#   macshell-setwall.sh --restore     re-apply the saved animated wallpaper at login (no-op if none)
#   macshell-setwall.sh --prepare <video>   only build the cached files (thumbnail frame + optimized copy)
# Prints the still image the Liquid Glass should refract (the picture itself, or a frame grabbed from the video).
# The current animated wallpaper is remembered in ~/.config/macshell/wallpaper-video (MacLock reads it too).
#
# Performance: videos are never played as-is. A 4K/60 fps clip decoded twice (one per monitor) cost ~45% CPU and
# could wake the NVIDIA GPU. Each video gets a cached copy sized to the largest monitor at 30 fps (H.264, decoded
# on the Intel iGPU via VA-API): ~5% CPU. The copy is built once in the background; the still frame shows meanwhile.
state="$HOME/.config/macshell/wallpaper-video"
cache="$HOME/.cache/macshell"
mkdir -p "$HOME/.config/macshell" "$cache/frames" "$cache/anim"

# Intel render node (never the NVIDIA one, so the dGPU can stay asleep)
igpu=""
for n in /dev/dri/renderD*; do
    [ "$(basename "$(readlink -f "/sys/class/drm/$(basename "$n")/device/driver")")" = i915 ] && { igpu="$n"; break; }
    [ "$(basename "$(readlink -f "/sys/class/drm/$(basename "$n")/device/driver")")" = xe ] && { igpu="$n"; break; }
done
MPV_OPTS="no-audio loop-file=inf profile=fast panscan=1.0 hwdec=vaapi${igpu:+ vaapi-device=$igpu} vd-lavc-threads=2 framedrop=vo"

is_video() { case "$(printf %s "$1" | tr 'A-Z' 'a-z')" in *.mp4|*.webm|*.mkv|*.mov|*.m4v) return 0 ;; esac; return 1; }
key_of() { printf '%s:%s' "$1" "$(stat -c %Y "$1" 2>/dev/null)" | md5sum | cut -c1-16; }

frame_for() {
    out="$cache/frames/$(key_of "$1").png"
    [ -s "$out" ] || ffmpeg -loglevel error -y -ss 1 -i "$1" -frames:v 1 "$out" </dev/null \
        || ffmpeg -loglevel error -y -i "$1" -frames:v 1 "$out" </dev/null
    printf '%s' "$out"
}

# small looping preview for the pickers (animated WebP: no video player needed inside the shell)
preview_for() {
    k=$(key_of "$1"); mkdir -p "$cache/thumbs"
    t="$cache/thumbs/$k.jpg"; w="$cache/thumbs/$k.webp"
    [ -s "$t" ] || ffmpeg -loglevel error -y -ss 1 -i "$1" -frames:v 1 -vf "scale=480:-2" "$t" </dev/null
    [ -s "$w" ] || nice -n 15 ffmpeg -loglevel error -y -t 4 -i "$1" -an -vf "fps=12,scale=360:-2:flags=lanczos" \
        -c:v libwebp_anim -lossless 0 -q:v 60 -loop 0 "$w" </dev/null
}

# low-res looping animated WebP of the whole clip: what the Liquid Glass (widgets) refracts — it's blurred anyway,
# so 480 px at 15 fps is plenty, and an image needs no video player inside the shell
glass_for() {
    k=$(key_of "$1"); g="$cache/anim/$k-glass.webp"
    [ -s "$g" ] || nice -n 15 ionice -c3 ffmpeg -loglevel error -y -i "$1" -an -vf "fps=15,scale=480:-2:flags=bilinear" \
        -c:v libwebp_anim -lossless 0 -q:v 45 -compression_level 3 -loop 0 "$g.part.webp" </dev/null && mv -f "$g.part.webp" "$g"
    printf '%s' "$g"
}

# width of the widest monitor (logical px), at least 1280
target_width() {
    w=$(hyprctl -j monitors 2>/dev/null | jq '[.[] | (.width / .scale)] | max | floor' 2>/dev/null)
    case "$w" in ''|null|*[!0-9]*) w=1920 ;; esac
    [ "$w" -lt 1280 ] && w=1280
    printf '%s' "$w"
}

# optimized copy: largest-monitor width, 30 fps, H.264, keyframe every 2 s
anim_for() {
    tw=$(target_width)
    out="$cache/anim/$(key_of "$1")-$tw.mp4"
    if [ ! -s "$out" ]; then
        tmp="$out.part.mp4"
        nice -n 15 ionice -c3 ffmpeg -loglevel error -y -i "$1" -an \
            -vf "scale='min($tw,iw)':-2:flags=lanczos,fps=30" \
            -c:v libx264 -preset faster -crf 21 -pix_fmt yuv420p -g 60 -movflags +faststart "$tmp" </dev/null \
            && mv -f "$tmp" "$out" || { rm -f "$tmp"; printf '%s' "$1"; return; }
    fi
    printf '%s' "$out"
}

awww_ready() {
    awww query >/dev/null 2>&1 && return 0
    pgrep -x awww-daemon >/dev/null || { setsid awww-daemon >/dev/null 2>&1 & }
    for i in 1 2 3 4 5 6 7 8 9 10; do awww query >/dev/null 2>&1 && return 0; sleep 0.3; done
    return 1
}

supfile="$cache/wallsup.pid"
stop_video() {
    # the supervisor runs in its own process group (setsid): stop the whole group, nothing else
    if [ -f "$supfile" ]; then
        g=$(cat "$supfile" 2>/dev/null)
        [ -n "$g" ] && kill -TERM -- "-$g" 2>/dev/null
        rm -f "$supfile"
    fi
    # mpvpaper can ignore SIGTERM (and a Game Mode SIGSTOP blocks it): wake it, ask, then force it
    pkill -CONT -x mpvpaper 2>/dev/null
    pkill -TERM -x mpvpaper 2>/dev/null
    for i in 1 2 3 4 5; do pgrep -x mpvpaper >/dev/null || break; sleep 0.1; done
    pkill -KILL -x mpvpaper 2>/dev/null
}

# keeps mpvpaper running for as long as this video is the chosen wallpaper (restarts it if it crashes)
start_video() {
    src="$1"; play="$2"
    stop_video
    printf '%s\n' "$play" > "$HOME/.config/macshell/wallpaper-video-play"     # the optimized copy (MacLock plays this one)
    # one supervised mpvpaper per monitor, each with an IPC socket: MacShell pauses a monitor's video while windows
    # cover it (or the screen is locked) and resumes it when the desktop shows again — no decoding nobody can see
    outs=$(hyprctl -j monitors 2>/dev/null | jq -r '.[].name' 2>/dev/null); [ -n "$outs" ] || outs=ALL
    run="${XDG_RUNTIME_DIR:-/tmp}"
    setsid sh -c '
        echo $$ > "$5"
        src="$1"; play="$2"; state="$3"; opts="$4"; run="$6"; shift 6
        for out in "$@"; do
            (
                fails=0
                while [ "$(cat "$state" 2>/dev/null)" = "$src" ] && [ "$fails" -lt 5 ]; do
                    t=$(date +%s)
                    mpvpaper -o "$opts input-ipc-server=$run/macshell-mpv-$out.sock" "$out" "$play" >/dev/null 2>&1 </dev/null
                    [ "$(cat "$state" 2>/dev/null)" = "$src" ] || exit 0
                    [ $(( $(date +%s) - t )) -lt 10 ] && fails=$((fails + 1)) || fails=0
                    sleep 1
                done
            ) &
        done
        wait
    ' wallsup "$src" "$play" "$state" "$MPV_OPTS" "$supfile" "$run" $outs >/dev/null 2>&1 </dev/null &
}

case "$1" in
    --prepare) [ -f "$2" ] && is_video "$2" && { preview_for "$2"; frame_for "$2" >/dev/null; a=$(anim_for "$2"); glass_for "$a" >/dev/null; }; exit 0 ;;
    --restore)
        [ -f "$state" ] || exit 0
        f=$(cat "$state")
        [ -f "$f" ] || { rm -f "$state"; exit 0; } ;;
    *) f="$1" ;;
esac
[ -f "$f" ] || { echo "no such file: $f" >&2; exit 1; }

if is_video "$f"; then
    still=$(frame_for "$f")
    printf '%s\n' "$f" > "$state"
    # the frame goes up first, so there is never a black flash and the glass has something to refract right away
    awww_ready && [ -s "$still" ] && awww img "$still" --transition-type grow --transition-duration 0.8 >/dev/null 2>&1
    printf '%s\n' "$still"
    # build the optimized copy in the background (only the first time), then play it
    (
        play=$(anim_for "$f")
        [ "$(cat "$state" 2>/dev/null)" = "$f" ] || exit 0      # another wallpaper was picked meanwhile
        start_video "$f" "$play"
        g=$(glass_for "$play")
        [ "$(cat "$state" 2>/dev/null)" = "$f" ] && [ -s "$g" ] && printf '%s\n' "$g" > "$HOME/.config/macshell/wallpaper-video-glass"
    ) >/dev/null 2>&1 </dev/null &
else
    rm -f "$state" "$HOME/.config/macshell/wallpaper-video-play" "$HOME/.config/macshell/wallpaper-video-glass"
    stop_video
    awww_ready && awww img "$f" --transition-type grow --transition-duration 0.9 >/dev/null 2>&1
    printf '%s\n' "$f"
fi
