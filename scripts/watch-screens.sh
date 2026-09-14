#!/usr/bin/env bash
# Rung 2b of the test ladder: render every watch state on the watch simulator from a fixed status
# (WATCH_STATE, no phone) and screenshot it. Compare the pictures against the control inventory at the
# top of docs/stories/05-watch.md. Usage: watch-screens.sh [watch simulator name].
set -uo pipefail
WATCH=${1:-"Apple Watch Series 11 (46mm)"}
BUNDLE=com.idvorkin.exerciseanalyzer.watchkitapp
SCREENS=${SCREENS:-$HOME/tmp/agent/sim}
WATCHAPP=$(find Build/Build/Products/Debug-iphonesimulator -maxdepth 4 -name "ExerciseAnalyzerWatch.app" 2>/dev/null | head -1)
if [ -z "${WATCHAPP:-}" ]; then
  echo "FAIL  no ExerciseAnalyzerWatch.app under Build/Build/Products/Debug-iphonesimulator (run just build-sim first)"
  exit 1
fi
mkdir -p "$SCREENS"
xcrun simctl boot "$WATCH" 2>/dev/null || true
xcrun simctl install "$WATCH" "$WATCHAPP" >/dev/null
fail=0
shoot() {  # state: relaunch with the fixed state, wait for first render, screenshot
  xcrun simctl terminate "$WATCH" "$BUNDLE" 2>/dev/null || true
  SIMCTL_CHILD_WATCH_STATE="$1" xcrun simctl launch "$WATCH" "$BUNDLE" >/dev/null || true
  sleep 3
  local shot="$SCREENS/watch-$1.png"
  xcrun simctl io "$WATCH" screenshot "$shot" 2>/dev/null || true
  if [ -f "$shot" ]; then echo "ok    $1: $shot"; else echo "FAIL  $1: no screenshot"; fail=1; fi
}
for state in disconnected background idle live recording paused done viewfinder; do shoot "$state"; done
exit $fail
