#!/usr/bin/env bash
# Rung 2 of the test ladder: run each sample clip through the simulator build and check the log.
# Usage: sim-smoke.sh <simulator name or udid> <bundle id> <app path>. Clips come from $SAMPLES (mp4s).
set -euo pipefail
SIM=$1; BUNDLE=$2; APP=$3
SAMPLES=${SAMPLES:-$HOME/tmp/agent/swing-samples}
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"
LOGS="$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)/Documents/logs"
fail=0
newest_log() { ls -t "$LOGS"/*.jsonl 2>/dev/null | head -1; }
# Waits (up to $2 s) until the newest log has an event of type $1; the simulator runs the model on the CPU, so a
# clip can take a few times its own length to analyze.
wait_for() {
  local waited=0
  while [ "$waited" -lt "$2" ]; do
    sleep 2; waited=$((waited + 2))
    local f; f=$(newest_log)
    [ -n "$f" ] && jq -e --arg t "$1" 'select(.type==$t)' "$f" >/dev/null 2>&1 && return 0
  done
  return 1
}
check() {  # clip expected-exercise expected-reps timeout-seconds
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
  local before; before=$(newest_log)
  SIMCTL_CHILD_SWING_VIDEO="$SAMPLES/$1.mp4" xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null
  sleep 3
  wait_for analyzed "$4" || echo "      (timed out after $4 s waiting for analysis)"
  local f; f=$(newest_log)
  local ex reps
  ex=$(jq -r 'select(.type=="detection") | .exercise' "$f" | tail -1)
  reps=$(jq -r 'select(.type=="analyzed") | .reps' "$f" | tail -1)
  if [ "$ex" = "$2" ] && [ "$reps" = "$3" ]; then echo "ok    $1: $ex, $reps reps";
  else echo "FAIL  $1: got $ex/$reps reps, wanted $2/$3"; fail=1; fi
}
check_trim() {  # clip expected-reps wait-seconds: auto-trims after analysis, expects a lossless cut that plays from 0
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
  SIMCTL_CHILD_SWING_VIDEO="$SAMPLES/$1.mp4" SIMCTL_CHILD_SWING_AUTO_TRIM=1 xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null
  sleep 3
  wait_for trim "$3" || echo "      (timed out after $3 s waiting for the trim)"
  sleep 4  # let the trimmed item install and display its first frames
  local f; f=$(newest_log)
  local pass start req first reps
  pass=$(jq -r 'select(.type=="trim_done") | .passthrough' "$f" | tail -1)
  start=$(jq -r 'select(.type=="trim") | .start_s' "$f" | tail -1)
  req=$(jq -r 'select(.type=="trim") | .requested_start_s' "$f" | tail -1)
  reps=$(jq -r 'select(.type=="trim") | .reps' "$f" | tail -1)
  # first displayed frame of the trimmed item: the player must start at the cut, not at the next keyframe
  first=$(jq -r 'select(.type=="display_frame") | .player_time' "$f" | tail -3 | sort -n | head -1)
  if [ "$pass" = "true" ] && [ "$reps" = "$2" ] && awk "BEGIN{exit !($start <= $req && $req - $start < 1.5 && $first < 0.2)}"; then
    echo "ok    trim $1: passthrough, start $start (asked $req), first frame at ${first}s, $reps reps"
  else echo "FAIL  trim $1: passthrough=$pass start=$start asked=$req first_frame=$first reps=$reps (wanted $2)"; fail=1; fi
}
check_cancel() {  # clip wait-seconds: cancels one second into the analysis (#37), expects the pass to stop within 3 s
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
  SIMCTL_CHILD_SWING_VIDEO="$SAMPLES/$1.mp4" SIMCTL_CHILD_SWING_CANCEL_ANALYSIS=1 xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null
  sleep 3
  wait_for analysis_cancelled "$2" || echo "      (timed out after $2 s waiting for the cancel to land)"
  local f; f=$(newest_log)
  local asked landed analyzed
  asked=$(jq -r 'select(.type=="analysis_cancel") | .t' "$f" | head -1)
  landed=$(jq -r 'select(.type=="analysis_cancelled") | .t' "$f" | head -1)
  analyzed=$(jq -r 'select(.type=="analyzed" or .type=="recents_saved") | .type' "$f" | head -1)
  if [ -n "$asked" ] && [ -n "$landed" ] && [ -z "$analyzed" ] && [ $((landed - asked)) -lt 3000 ]; then
    echo "ok    cancel $1: stopped $((landed - asked)) ms after Cancel, nothing analyzed or saved"
  else echo "FAIL  cancel $1: asked=$asked landed=$landed analyzed=$analyzed"; fail=1; fi
}
# ONLY=<substring> runs just the matching checks (e.g. ONLY=trim).
run() { if [ -z "${ONLY:-}" ] || [[ "$*" == *"${ONLY}"* ]]; then "$@"; fi; }
run check swing-sample-4reps kettlebell-swing 4 90
run check pistols pistol-squat 6 180
run check bulgarian bulgarian-split-squat 8 180
run check_trim igor-1h-swing 9 150
run check_cancel pistols 60
exit $fail
