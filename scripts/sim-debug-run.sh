#!/usr/bin/env bash
# Rung 2 for the instrumented run (story 036): put one set in the simulator's Workouts by analyzing a sample clip,
# relaunch with SWING_DEBUG_RUN=1, and check that the run starts, shows its banner (a screenshot lands in
# ~/tmp/agent/sim/), goes through the set with the detector on, and ends with the held-bell numbers in the log.
# Usage: sim-debug-run.sh <simulator name> <bundle id> <app path>
set -uo pipefail
SIM=$1 BUNDLE=$2 APP=$3
SAMPLES=$HOME/tmp/agent/swing-samples
SHOTS=$HOME/tmp/agent/sim
mkdir -p "$SHOTS"
xcrun simctl boot "$SIM" >/dev/null 2>&1 || true
xcrun simctl install "$SIM" "$APP"
LOGS="$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)/Documents/logs"
newest_log() { ls -t "$LOGS"/*.jsonl 2>/dev/null | head -1; }
wait_for() { # <event type> <seconds>: until the newest log has one
  local waited=0
  while [ "$waited" -lt "$2" ]; do
    sleep 2; waited=$((waited + 2))
    local f; f=$(newest_log)
    [ -n "$f" ] && grep -q "\"type\":\"$1\"" "$f" && return 0
  done
  echo "FAIL: no $1 within $2 s"; return 1
}
launch() { xcrun simctl terminate "$SIM" "$BUNDLE" >/dev/null 2>&1; sleep 1; env "$@" xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null; }

echo "1. a set in Workouts (the 4-rep swing through the models; the simulator runs them on the CPU)"
launch SIMCTL_CHILD_SWING_VIDEO="$SAMPLES/swing-sample-4reps.mp4" SIMCTL_CHILD_SWING_BELLS=1
wait_for recents_saved 240 || exit 1

echo "2. relaunch into an instrumented run"
launch SIMCTL_CHILD_SWING_DEBUG_RUN=1
wait_for debug_run 120 || exit 1
sleep 3
xcrun simctl io "$SIM" screenshot "$SHOTS/debug-run.png" >/dev/null 2>&1 && echo "   banner screenshot: $SHOTS/debug-run.png"
wait_for bell_held 300 || exit 1
sleep 4
f=$(newest_log)
echo "3. the log:"
jq -c 'select(.type == "debug_run" or .type == "recents_rerun" or .type == "offline_pass" or .type == "bell_held" or .type == "error")
  | del(.thread)' "$f"
grep -q '"phase":"end"' "$f" && echo "PASS: instrumented run ended" || { echo "FAIL: no debug_run end"; exit 1; }
