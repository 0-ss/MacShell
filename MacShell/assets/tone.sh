#!/bin/sh
# Prints "<brightness> <spread>" (both 0..1, perceived/gamma brightness) of a screen area, read by MacBar.qml (auto contrast).
#   tone.sh SCALE X Y W H [IX IY IW IH]
# The area X,Y WxH is grabbed with grim (wallpaper + every window + layers = what is really on screen). With IX IY IW IH given,
# that inner rectangle (the open panel itself) is left out, so the panel's own glass never feeds back into the measurement.
# The brightness is taken after a median filter, so thin text (the bar's own labels) does not tilt it.
t=$(mktemp /tmp/macshell-tone.XXXXXX) || exit 1
trap 'rm -f "$t"' EXIT
s=${1:-0.1}; X=$2; Y=$3; W=$4; H=$5
grim -t ppm -s "$s" -g "$X,$Y ${W}x$H" "$t" 2>/dev/null || exit 1
L='0.299*mean.r+0.587*mean.g+0.114*mean.b'
D='0.299*standard_deviation.r+0.587*standard_deviation.g+0.114*standard_deviation.b'
mo=$(magick "$t" -statistic Median 3x3 -format "%[fx:$L]" info: 2>/dev/null) || exit 1
sd=$(magick "$t" -format "%[fx:$D]" info: 2>/dev/null) || exit 1
if [ -n "$9" ] && [ "$8" -gt 0 ] 2>/dev/null; then
  iw=$(magick "$t" -format '%w %h' info: 2>/dev/null)
  geo=$(awk -v iw="$iw" -v X="$X" -v Y="$Y" -v W="$W" -v H="$H" -v ix="$6" -v iy="$7" -v w="$8" -v h="$9" 'BEGIN {
    split(iw, a, " "); rx = a[1] / W; ry = a[2] / H;
    cx = int((ix - X) * rx); cy = int((iy - Y) * ry); cw = int(w * rx); ch = int(h * ry);
    if (cx < 0) { cw += cx; cx = 0 } if (cy < 0) { ch += cy; cy = 0 }
    if (cx + cw > a[1]) cw = a[1] - cx; if (cy + ch > a[2]) ch = a[2] - cy;
    print cw, ch, cx, cy, a[1], a[2] }')
  set -- $geo
  if [ "$1" -gt 0 ] 2>/dev/null && [ "$2" -gt 0 ] 2>/dev/null; then
    mi=$(magick "$t" -crop "${1}x${2}+${3}+${4}" +repage -statistic Median 3x3 -format "%[fx:$L]" info: 2>/dev/null)
    mo=$(awk -v mo="$mo" -v mi="$mi" -v a="$1" -v b="$2" -v W="$5" -v H="$6" 'BEGIN {
      tot = W * H; inn = a * b; if (tot - inn < tot * 0.08 || mi == "") { print mo; exit }
      print (mo * tot - mi * inn) / (tot - inn) }')
  fi
fi
echo "$mo $sd"
