#!/usr/bin/env bash
# Ground truth for the bell tracker: cut sampled frames from a clip and draw where the tracker put the bell (a
# circle) and the wrists (small squares), so a vision model or Igor can say whether the dot is on the bell in the
# hands. Input: a DOT dump from `BELL_LAB_DOTS=1 swift test --filter TuningReports/testBellTrackerHeldPerFixture`
#   DOT <fixture> <frame> <time> <cx> <cy> <w> <h> <conf> <wrists: x,y/x,y or ->
# Usage: cut-dot-frames.sh <dots file> <fixture name> <clip path> <n frames> <out dir>
#   A seeded random sample of n frames, so a rerun after a tracker change cuts the same frames; or, with
#   FRAMES="225 533 ..." in the environment, exactly those frame indices.
set -uo pipefail
dots=$1 name=$2 clip=$3 n=$4 out=$5
mkdir -p "$out"
pick() {
  if [ -n "${FRAMES:-}" ]; then
    for f in $FRAMES; do grep "^DOT $name $f " "$dots"; done | sed 's/^/0\t/'
  else
    grep "^DOT $name " "$dots" | awk 'BEGIN{srand(7)} {print rand() "\t" $0}' | sort -n | head -n "$n" | cut -f2- | sed 's/^/0\t/'
  fi
}
pick | cut -f2- | sort -k3,3n |
while read -r _ fx frame time cx cy w h conf wrists; do
  png="$out/$name-$frame.png"
  ffmpeg -loglevel error -y -ss "$time" -i "$clip" -frames:v 1 "$png.raw.png" || { echo "no frame $frame"; continue; }
  read -r W H < <(magick identify -format "%w %h" "$png.raw.png")
  draw=""
  if [ "$cx" != "-" ]; then
    # a circle in yellow at the tracked bell, radius from the box
    r=$(awk -v w="$w" -v W="$W" 'BEGIN{printf "%d", (w*W)/2}')
    draw="$draw -stroke yellow -strokewidth 5 -fill none -draw \"circle $(awk -v x="$cx" -v W="$W" 'BEGIN{printf "%d", x*W}'),$(awk -v y="$cy" -v H="$H" 'BEGIN{printf "%d", y*H}') $(awk -v x="$cx" -v W="$W" -v r="$r" 'BEGIN{printf "%d", x*W + r}'),$(awk -v y="$cy" -v H="$H" 'BEGIN{printf "%d", y*H}')\""
  fi
  if [ "$wrists" != "-" ]; then
    for wr in ${wrists//\// }; do
      wx=${wr%%,*}; wy=${wr#*,}
      px=$(awk -v x="$wx" -v W="$W" 'BEGIN{printf "%d", x*W}'); py=$(awk -v y="$wy" -v H="$H" 'BEGIN{printf "%d", y*H}')
      draw="$draw -stroke cyan -strokewidth 4 -fill none -draw \"rectangle $((px-12)),$((py-12)) $((px+12)),$((py+12))\""
    done
  fi
  eval magick "$png.raw.png" $draw -resize 960x "$png" && rm -f "$png.raw.png"
  echo "$png t=$time dot=$cx,$cy conf=$conf"
done
