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
check() {  # clip expected-exercise expected-reps wait-seconds
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
  SIMCTL_CHILD_SWING_VIDEO="$SAMPLES/$1.mp4" xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null
  sleep "$4"
  local f; f=$(ls -t "$LOGS"/*.jsonl | head -1)
  local ex reps
  ex=$(jq -r 'select(.type=="detection") | .exercise' "$f" | tail -1)
  reps=$(jq -r 'select(.type=="analyzed") | .reps' "$f" | tail -1)
  if [ "$ex" = "$2" ] && [ "$reps" = "$3" ]; then echo "ok    $1: $ex, $reps reps";
  else echo "FAIL  $1: got $ex/$reps reps, wanted $2/$3"; fail=1; fi
}
check swing-sample-4reps kettlebell-swing 4 18
check pistols pistol-squat 6 45
check bulgarian bulgarian-split-squat 10 50
exit $fail
