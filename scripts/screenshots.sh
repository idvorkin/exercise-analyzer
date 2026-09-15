#!/usr/bin/env bash
# Captures README screenshots from the simulator build. Each shot launches the app with a sample clip through the
# SWING_VIDEO hook, presets the view through user defaults, waits for the analysis, and grabs the screen.
# Usage: scripts/screenshots.sh <simulator name> <bundle id> <app path>   (clips from $SAMPLES, see sim-smoke.sh)
set -euo pipefail
SIM=$("$(dirname "$0")/sim-udid.sh" "$1"); BUNDLE=$2; APP=$3  # one device, whatever runtimes share the name
SAMPLES=${SAMPLES:-$HOME/tmp/agent/swing-samples}
OUT="$(pwd)/docs/screenshots"
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"
LOGS="$(xcrun simctl get_app_container "$SIM" "$BUNDLE" data)/Documents/logs"
newest_log() { ls -t "$LOGS"/*.jsonl 2>/dev/null | head -1; }
wait_for() {  # event-type timeout-seconds
  local waited=0
  while [ "$waited" -lt "$2" ]; do
    sleep 2; waited=$((waited + 2))
    local f; f=$(newest_log)
    [ -n "$f" ] && jq -e --arg t "$1" 'select(.type==$t)' "$f" >/dev/null 2>&1 && return 0
  done
  return 1
}
shoot() {  # name clip overlayMode meView extra-wait
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
  xcrun simctl spawn "$SIM" defaults write "$BUNDLE" overlayMode -string "$3"
  xcrun simctl spawn "$SIM" defaults write "$BUNDLE" meView -bool "$4"
  xcrun simctl spawn "$SIM" defaults write "$BUNDLE" galleryHeight -float 210
  SIMCTL_CHILD_SWING_VIDEO="$SAMPLES/$2.mp4" xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null
  sleep 3
  wait_for analyzed 240 || echo "timed out waiting for $2"
  sleep "$5"
  xcrun simctl io "$SIM" screenshot --type png "$OUT/$1.png" >/dev/null
  sips --resampleWidth 480 "$OUT/$1.png" >/dev/null   # keep the repo small
  echo "shot $1"
}
shoot swing-analysis swing-sample-4reps both true 6
shoot bulgarian-split-squat bulgarian both true 6
shoot pistol-squat pistols both false 6
xcrun simctl spawn "$SIM" defaults write "$BUNDLE" overlayMode -string both
