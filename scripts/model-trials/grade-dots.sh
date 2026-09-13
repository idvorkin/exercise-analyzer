#!/usr/bin/env bash
# Ground truth for the bell tracker, graded by Muse (Igor's Muse Code contributor model can look at images and is
# cheap): every PNG from cut-dot-frames.sh in a directory is sent headless with the rubric, several at a time, and
# the answers land in <dir>/labels-muse.csv with a per-clip summary printed (bell in hands, circle on it = recall,
# circles on something else = false holds). Usage: grade-dots.sh <dir> [parallel, default 6]
set -uo pipefail
dir=$1 par=${2:-3}
here=$(cd "$(dirname "$0")" && pwd)
rubric=$here/grade-dots-rubric.txt
out=$dir/labels-muse.csv
# Resumable: frames already in the CSV are skipped (a run of six in parallel got killed for memory beside the
# interactive Muse; three is safe on a 16 GB Mac with nothing else heavy).
[ -s "$out" ] || echo "file,circle,bell_in_hands,circle_on,note" > "$out"
grade() { # one frame → one CSV line on stdout
  local png=$1 answer
  answer=$(cd "$(dirname "$png")" && muse exec --image "$png" --reasoning-effort low --prompt-file "$RUBRIC" 2>/dev/null | grep -E '^\{' | tail -1)
  local circle in on note
  circle=$(printf '%s' "$answer" | jq -r '.circle // "?"' 2>/dev/null)
  in=$(printf '%s' "$answer" | jq -r '.bell_in_hands // "?"' 2>/dev/null)
  on=$(printf '%s' "$answer" | jq -r '.circle_on // "?"' 2>/dev/null)
  note=$(printf '%s' "$answer" | jq -r '.note // ""' 2>/dev/null | tr ',' ';')
  echo "$(basename "$png"),${circle:-?},${in:-?},${on:-?},${note}"
}
export -f grade
export RUBRIC=$rubric
find "$dir" -maxdepth 1 -name '*.png' | sort | while read -r png; do
  grep -q "^$(basename "$png")," "$out" || echo "$png"
done | xargs -P "$par" -I{} bash -c 'grade "$1"' _ {} >> "$out"
echo "graded $(($(wc -l < "$out") - 1)) frames into $out"
# per clip: frames, bell in hands, circle on it, false holds and what they were on
awk -F, 'NR > 1 {
  clip = $1; sub(/-[0-9]+\.png$/, "", clip)
  frames[clip]++
  if ($3 == "yes") { inhand[clip]++; if ($4 == "hand_bell") rec[clip]++ }
  if ($2 == "yes" && $4 != "hand_bell") { fh[clip]++; what[clip] = what[clip] " " $4 }
}
END { for (c in frames) printf "  %s: %d frames, bell in hands %d, circle on it %d, false holds %d (%s)\n", c, frames[c], inhand[c], rec[c], fh[c], what[c] }' "$out" | sort
