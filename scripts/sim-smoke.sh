#!/usr/bin/env bash
# Rung 2 of the test ladder: run each sample clip through the simulator build and check the log.
# Usage: sim-smoke.sh <simulator name or udid> <bundle id> <app path>. Clips come from $SAMPLES (mp4s).
set -euo pipefail
SIM=$("$(dirname "$0")/sim-udid.sh" "$1"); BUNDLE=$2; APP=$3  # one device, whatever runtimes share the name
SAMPLES=${SAMPLES:-$HOME/tmp/agent/swing-samples}
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"
LOGS="$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)/Documents/logs"
fail=0
newest_log() { ls -t "$LOGS"/*.jsonl 2>/dev/null | head -1; return 0; }  # no logs yet on a fresh install
# Waits (up to $2 s) until the newest log has an event of type $1; the simulator runs the model on the CPU, so a
# clip can take a few times its own length to analyze.
wait_for() {
  local waited=0
  while [ "$waited" -lt "$2" ]; do
    sleep 2; waited=$((waited + 2))
    local f; f=$(newest_log)
    [ -n "$f" ] && [ "$f" != "$previous_log" ] && jq -e --arg t "$1" 'select(.type==$t)' "$f" >/dev/null 2>&1 && return 0
  done
  fail=1  # A timeout must fail the run even if the following assertion finds a matching old result.
  return 1
}
# A mode-switching check must not leak its exercise into later launches (#57): terminate, then drop the
# persisted mode default (absent on a fresh simulator; deleting a missing key is fine).
reset_mode() {
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
  xcrun simctl spawn "$SIM" defaults delete "$BUNDLE" exerciseMode 2>/dev/null || true
  previous_log=$(newest_log)
}
check() {  # clip expected-exercise expected-reps timeout-seconds
  reset_mode
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
  reset_mode
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
  first=$(jq -sr '
    ([.[] | select(.type=="trim")][-1].t) as $trim |
    [.[] | select(.type=="display_frame" and .t >= $trim)][0].player_time // empty
  ' "$f")
  if [ "$pass" = "true" ] && [ "$reps" = "$2" ] && awk "BEGIN{exit !($start <= $req && $req - $start < 1.5 && $first < 0.2)}"; then
    echo "ok    trim $1: passthrough, start $start (asked $req), first frame at ${first}s, $reps reps"
  else echo "FAIL  trim $1: passthrough=$pass start=$start asked=$req first_frame=$first reps=$reps (wanted $2)"; fail=1; fi
}
check_cancel() {  # clip wait-seconds: cancels one second into the analysis (#37), expects the pass to stop within 3 s
  reset_mode
  SIMCTL_CHILD_SWING_VIDEO="$SAMPLES/$1.mp4" SIMCTL_CHILD_SWING_CANCEL_ANALYSIS=1 xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null
  sleep 3
  wait_for analysis_cancelled "$2" || echo "      (timed out after $2 s waiting for the cancel to land)"
  sleep 2  # observe the completion path too: Cancel must not fall through to playback
  local f; f=$(newest_log)
  local asked landed analyzed played
  asked=$(jq -r 'select(.type=="analysis_cancel") | .t' "$f" | head -1)
  landed=$(jq -r 'select(.type=="analysis_cancelled") | .t' "$f" | head -1)
  analyzed=$(jq -r 'select(.type=="analyzed" or .type=="recents_saved") | .type' "$f" | head -1)
  played=$(jq -r 'select(.type=="play") | .t' "$f" | head -1)
  if [ -n "$asked" ] && [ -n "$landed" ] && [ -z "$analyzed" ] && [ -z "$played" ] && [ $((landed - asked)) -lt 3000 ]; then
    echo "ok    cancel $1: stopped $((landed - asked)) ms after Cancel, paused, nothing analyzed or saved"
  else echo "FAIL  cancel $1: asked=$asked landed=$landed analyzed=$analyzed played=$played"; fail=1; fi
}
check_interrupt() {  # clip interrupt-frame mode expected-reps wait-seconds: fails the first pass the way a
  # backgrounded decoder does (#57); the mode switch must then re-run the clip, so an offline_pass comes before
  # any analyzed and the failed pass alone analyzes nothing.
  reset_mode
  SIMCTL_CHILD_SWING_VIDEO="$SAMPLES/$1.mp4" SIMCTL_CHILD_SWING_INTERRUPT_READER="$2" SIMCTL_CHILD_SWING_MODE="$3" \
    xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null
  sleep 3
  wait_for offline_interrupted "$5" || echo "      (timed out after $5 s waiting for the interruption)"
  wait_for analyzed "$5" || echo "      (timed out after $5 s waiting for the re-run analysis)"
  local f; f=$(newest_log)
  local interrupted mode pass analyzed reps
  interrupted=$(jq -r 'select(.type=="offline_interrupted") | .t' "$f" | head -1)
  mode=$(jq -r 'select(.type=="exercise_mode") | .t' "$f" | head -1)
  pass=$(jq -r 'select((.type=="offline_pass") and (.where == null)) | .t' "$f" | head -1)
  analyzed=$(jq -r 'select(.type=="analyzed") | .t' "$f" | head -1)
  reps=$(jq -r 'select(.type=="analyzed") | .reps' "$f" | tail -1)
  if [ -n "$interrupted" ] && [ -n "$mode" ] && [ -n "$pass" ] && [ -n "$analyzed" ] && [ "$reps" = "$4" ] \
    && [ "$interrupted" -lt "$mode" ] && [ "$mode" -lt "$pass" ] && [ "$pass" -lt "$analyzed" ]; then
    echo "ok    interrupt $1: failed at $interrupted, mode at $mode, pass at $pass, analyzed at $analyzed ($reps reps)"
  else echo "FAIL  interrupt $1: interrupted=$interrupted mode=$mode pass=$pass analyzed=$analyzed reps=$reps (wanted $4)"; fail=1; fi
  # The hook must not persist its mode: the next launch has to detect again (#57 pollution).
  local mode_default
  mode_default=$(xcrun simctl spawn "$SIM" defaults read "$BUNDLE" exerciseMode 2>/dev/null || true)
  if [ -n "$mode_default" ]; then echo "FAIL  interrupt $1: hook persisted exerciseMode=$mode_default"; fail=1; fi
}
check_clip_switch() {  # stage: force A's render/replay/Photos/trim result to arrive after stored B opens
  reset_mode
  SIMCTL_CHILD_SWING_VIDEO="$SAMPLES/swing-sample-4reps.mp4" SIMCTL_CHILD_SWING_CLIP_SWITCH="$1" \
    xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null
  sleep 3
  wait_for clip_switch_checked 120 || echo "      (timed out waiting for clip switch)"
  local f; f=$(newest_log)
  if jq -se '
    ([.[] | select(.type=="clip_switch_begin")][0].t) as $start |
    ([.[] | select(.type=="clip_switch_checked")][-1]) as $result |
    $start != null and $result.current_b == true and $result.reps == 0 and
    $result.local_exists == true and $result.entry_unchanged == true and $result.idle == true and
    ([.[] | select(.t >= $start and (.type=="analyzed" or .type=="recents_saved" or .type=="saved" or .type=="trim"))] | length) == 0 and
    ([.[] | select(.t >= $start and .type=="play")] | length) == 1
  ' "$f" >/dev/null; then
    echo "ok    clip_switch $1: B retained, zero reps, local video intact, no stale save or playback"
  else echo "FAIL  clip_switch $1: $f"; fail=1; fi
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
}
check_live_workout() {
  reset_mode
  SIMCTL_CHILD_SWING_LIVE_WORKOUT=2 SIMCTL_CHILD_SWING_WORKOUT_EVOLVE=1 \
    xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null
  wait_for workout_saved 60 || echo "      (timed out waiting for live workout to end)"
  sleep 2
  local f; f=$(newest_log)
  if jq -se '
    [.[] | select(.type=="workout_page")] as $pages |
    ([$pages[] | select(.live == true and .sets == 1)][0]) as $first |
    ([$pages[] | select(.live == true and .sets == 2)][-1]) as $later |
    ([$pages[] | select(.live == false)][-1]) as $saved |
    $first != null and $later != null and $saved != null and
    $later.reps == 16 and $later.duration_s > $first.duration_s + 15 and
    $later.window_s > $first.window_s + 15 and
    $saved.sets == 2 and $saved.reps == 16 and $saved.workout_id != "live" and
    ([.[] | select(.type=="workout_heart_rate")] | length) >= 3
  ' "$f" >/dev/null; then
    echo "ok    live_workout: 1 → 2 sets / 16 reps, clock and window advanced, Health re-asked, saved page retained both sets"
  else echo "FAIL  live_workout: $f"; fail=1; fi
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
}
# ONLY=<substring> runs just the matching checks (e.g. ONLY=trim).
run() { if [ -z "${ONLY:-}" ] || [[ "$*" == *"${ONLY}"* ]]; then "$@"; fi; }
run check swing-sample-4reps kettlebell-swing 4 90
run check pistols pistol-squat 6 180
run check bulgarian bulgarian-split-squat 8 180
run check_trim igor-1h-swing 9 150
run check_cancel pistols 60
run check_interrupt pistols 60 pistol-squat 6 180
run check_clip_switch render
run check_clip_switch mode
run check_clip_switch photos
run check_clip_switch trim
run check_live_workout
exit $fail
