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
check_cancel_reopen() {  # clip expected-reps wait-seconds: cancels one second in and reopens the clip at once while
  # the cancelled worker holds the models half a second longer (#147); the new pass must wait for them
  # (model_wait) and be the only pass that finishes.
  reset_mode
  SIMCTL_CHILD_SWING_VIDEO="$SAMPLES/$1.mp4" SIMCTL_CHILD_SWING_CANCEL_ANALYSIS=reopen xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null
  sleep 3
  wait_for analyzed "$3" || echo "      (timed out after $3 s waiting for the reopened pass)"
  local f; f=$(newest_log)
  local asked waited ms passes reps
  asked=$(jq -r 'select(.type=="analysis_cancel") | .t' "$f" | head -1)
  waited=$(jq -r 'select(.type=="model_wait" and .who=="pass") | .t' "$f" | head -1)
  ms=$(jq -r 'select(.type=="model_wait" and .who=="pass") | .ms' "$f" | head -1)
  passes=$(jq -r 'select(.type=="offline_pass" and .where == null) | .t' "$f" | wc -l | tr -d ' ')
  reps=$(jq -r 'select(.type=="analyzed") | .reps' "$f" | tail -1)
  if [ -n "$asked" ] && [ -n "$waited" ] && [ "$waited" -gt "$asked" ] && [ "${ms:-0}" -ge 250 ] \
    && [ "$passes" = "1" ] && [ "$reps" = "$2" ]; then
    echo "ok    cancel_reopen $1: second pass waited $ms ms for the models, one pass finished, $reps reps"
  else echo "FAIL  cancel_reopen $1: asked=$asked waited=$waited ms=$ms passes=$passes reps=$reps (wanted $2)"; fail=1; fi
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
# The simulator's own sets and workouts, moved aside and back (check_live_workout). A stash an interrupted run
# left behind is put back first, so the lifter's simulator data is never lost to it.
STASHED="recents/index.json workouts.json workouts"
unstash() {
  local docs stash p; docs=$(dirname "$LOGS"); stash="$docs/.smoke-stash"
  [ -d "$stash" ] || return 0
  for p in $STASHED; do
    if [ -e "$stash/$p" ]; then rm -rf "${docs:?}/$p"; mv "$stash/$p" "$docs/$p"
    elif [ -e "$stash/$p.absent" ]; then rm -rf "${docs:?}/$p"; fi
  done
  rm -rf "$stash"
}
stash() {
  local docs stash p; docs=$(dirname "$LOGS"); stash="$docs/.smoke-stash"
  unstash
  mkdir -p "$stash/recents"
  for p in $STASHED; do
    if [ -e "$docs/$p" ]; then mv "$docs/$p" "$stash/$p"; else touch "$stash/$p.absent"; fi
  done
}
# A run cut short (Ctrl-C, a failed command) puts the simulator's data back at once, so no stale ".absent"
# marker waits for a later run to delete data made in between (PR #175 review).
trap unstash EXIT
check_live_workout() {
  reset_mode
  # The pretend workout began 2 minutes ago, so the sets the checks before this one just saved, or a workout a
  # previous run saved (sessions merge under 30 minutes apart, #169), would land in it (#171): run it on an empty
  # list and put the simulator's own back after.
  stash
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
  # #178: a tap on the saved workout's chart where no set is adds a set by hand there, as Save on its sheet would.
  previous_log=$(newest_log)
  SIMCTL_CHILD_SWING_OPEN_WORKOUT=1 SIMCTL_CHILD_SWING_WORKOUT_BAR_TAP=0.05 SIMCTL_CHILD_SWING_WORKOUT_ADD_SAVE=1 \
    xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null
  wait_for set_by_hand 30 || echo "      (timed out waiting for the chart's set)"
  sleep 1
  f=$(newest_log)
  if jq -se '
    ([.[] | select(.type=="ui" and .action=="workout_bar_tap")][-1] | .hit == false and .adding == true) and
    ([.[] | select(.type=="set_by_hand")][-1] | .where == "workout_chart" and .duplicate == false and .at > 0) and
    ([.[] | select(.type=="workout_page")] | length >= 2 and .[-1].sets == .[0].sets + 1 and .[-1].reps > .[0].reps)
  ' "$f" >/dev/null; then
    echo "ok    add_from_chart: an empty tap on the chart added a set by hand, and the page counts it"
  else echo "FAIL  add_from_chart: $f"; fail=1; fi
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
  # 065: delete the workout just saved, as a confirmed long-press would. Its sets were the pretend watch's (no
  # video), so no set is saved here and none may appear or go.
  previous_log=$(newest_log)
  SIMCTL_CHILD_SWING_DELETE_WORKOUT=confirm xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null
  wait_for workout_deleted 30 || echo "      (timed out waiting for the workout delete)"
  sleep 1
  local docs; docs=$(dirname "$LOGS"); f=$(newest_log)
  if jq -se '[.[] | select(.type=="workout_deleted")][-1] | .rows == 1 and .message == ""' "$f" >/dev/null &&
    jq -e '.workouts | length == 0' "$docs/workouts.json" >/dev/null &&
    ! jq -se 'any(.[]; .type=="set_deleted")' "$f" >/dev/null; then
    echo "ok    delete_workout: the row gone, no set touched"
  else echo "FAIL  delete_workout: $f"; fail=1; fi
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
  unstash  # the check's own workout goes; the simulator's sets and workouts come back
}
check_bug_again() {  # #212: two reports from one shake ("Log it and another") both carry the screenshot and the frame
  reset_mode
  local docs; docs=$(dirname "$LOGS")
  local before; before=$(wc -l < "$docs/bugs.jsonl" 2>/dev/null || echo 0)
  SIMCTL_CHILD_SWING_VIDEO="$SAMPLES/swing-sample-4reps.mp4" SIMCTL_CHILD_SWING_BUG="first of two|second of two" \
    xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null
  wait_for bug_report 60 || echo "      (timed out waiting for the reports)"
  sleep 2
  local f; f=$(newest_log)
  if [ "$(wc -l < "$docs/bugs.jsonl")" -eq $((before + 2)) ] &&
    tail -2 "$docs/bugs.jsonl" | jq -se '
      length == 2 and .[0].note == "first of two" and .[1].note == "second of two" and
      all(.[]; (.screenshot | type) == "string" and (.frame | type) == "string" and .log != null)
    ' >/dev/null &&
    [ "$(jq -s '[.[] | select(.type=="bug_report")] | length' "$f")" = "2" ]; then
    echo "ok    bug_again: two reports from one capture, both with screenshot and frame"
  else echo "FAIL  bug_again: $f"; fail=1; fi
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
}
# ONLY=<substring> runs just the matching checks (e.g. ONLY=trim).
run() { if [ -z "${ONLY:-}" ] || [[ "$*" == *"${ONLY}"* ]]; then "$@"; fi; }
run check swing-sample-4reps kettlebell-swing 4 90
run check pistols pistol-squat 5 180  # 6 until the walk-in stopped counting (#171)
run check bulgarian bulgarian-split-squat 8 180
run check_trim igor-1h-swing 10 150  # 9 until the first swing counted (#148)
run check_cancel pistols 60
run check_cancel_reopen pistols 5 180
run check_interrupt pistols 60 pistol-squat 5 180
run check_clip_switch render
run check_clip_switch mode
run check_clip_switch photos
run check_clip_switch trim
check_photos_export() {  # 070 step 3: once approved, clips of sets not on screen go to Photos, and a set reopens from there
  reset_mode
  xcrun simctl privacy "$SIM" grant photos "$BUNDLE" >/dev/null 2>&1 || true
  # A spawn defaults write never changes a key the app already persisted (docs/TESTING.md): edit its plist, app terminated.
  local prefs; prefs="$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)/Library/Preferences/$BUNDLE.plist"
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
  [ -f "$prefs" ] || { mkdir -p "$(dirname "$prefs")"; plutil -create xml1 "$prefs"; }
  plutil -replace photosExportApproved -bool true "$prefs"
  restart_prefs
  local docs; docs=$(dirname "$LOGS")
  local before; before=$(jq '[.[] | select(.source.file != null)] | length' "$docs/recents/index.json")
  xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null  # nothing open: every in-app clip is due
  wait_for photos_export 120 || echo "      (timed out waiting for the first export)"
  sleep 15
  local f; f=$(newest_log)
  local exported left
  exported=$(jq -s '[.[] | select(.type=="photos_export")] | length' "$f")
  left=$(jq '[.[] | select(.source.file != null)] | length' "$docs/recents/index.json")
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
  # The newest set is now in the simulator's Photos: it opens from there, its stored analysis read, not re-run.
  previous_log=$(newest_log)
  SIMCTL_CHILD_SWING_OPEN_RECENT=1 xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null
  wait_for recents_open 60 || echo "      (timed out waiting for the reopened set)"
  local g; g=$(newest_log)
  if [ "$before" -gt 0 ] && [ "$exported" -eq "$before" ] && [ "$left" -eq 0 ] &&
    ! jq -se 'any(.[]; .type=="photos_export_failed")' "$f" >/dev/null &&
    jq -se '([.[] | select(.type=="photos_fetch")][-1] | .found == true) and any(.[]; .type=="recents_open")' "$g" >/dev/null; then
    echo "ok    photos_export: $exported clips into Photos, none left in the app, the newest set reopened from Photos"
  else echo "FAIL  photos_export: before=$before exported=$exported left=$left, $f $g"; fail=1; fi
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
  plutil -remove photosExportApproved "$prefs" 2>/dev/null || true
  restart_prefs
}
# The simulator's cfprefsd keeps an app's domain cached after the app quits: a plist edited behind it is not read
# at the next launch, and its next save writes the cached keys back. Restarting it makes it read the file again.
restart_prefs() {
  xcrun simctl spawn "$SIM" launchctl kill SIGTERM system/com.apple.cfprefsd.xpc.daemon >/dev/null 2>&1 || true
  sleep 1
}
run check_live_workout
run check_bug_again
run check_photos_export
exit $fail
