#!/usr/bin/env bash
# Rung 2 for the sync (story 070): two simulators, one plain folder standing in for the iCloud container.
# The phone simulator mirrors its sets and workouts (step 1); the iPad simulator reads them (step 2); a bell
# weight set and a set deleted on the iPad reach the phone (step 4). Clips are not checked here: the simulator
# has no iCloud Photos (step 3's cloud identifiers need two devices on one account).
# Usage: sync-smoke.sh <phone simulator> <ipad simulator> <bundle id> <app path>
set -euo pipefail
PHONE=$("$(dirname "$0")/sim-udid.sh" "$1"); IPAD=$("$(dirname "$0")/sim-udid.sh" "$2"); BUNDLE=$3; APP=$4
SYNC=$(mktemp -d "${TMPDIR:-/tmp}/sync-smoke.XXXXXX")
fail=0
for sim in "$PHONE" "$IPAD"; do
  xcrun simctl boot "$sim" 2>/dev/null || true
done
# The iPad starts empty (what it holds is copies of the phone's), so the read is a whole one with `added` > 0.
xcrun simctl uninstall "$IPAD" "$BUNDLE" 2>/dev/null || true
for sim in "$PHONE" "$IPAD"; do xcrun simctl install "$sim" "$APP"; done
docs() { echo "$(xcrun simctl get_app_container "$1" "$BUNDLE" data)/Documents"; }
newest_log() { ls -t "$(docs "$1")"/logs/*.jsonl 2>/dev/null | head -1; return 0; }
# Waits up to $3 s for the newest log of simulator $1 to carry an event of type $2 (after `since`).
wait_for() {
  local waited=0
  while [ "$waited" -lt "$3" ]; do
    sleep 2; waited=$((waited + 2))
    local f; f=$(newest_log "$1")
    [ -n "$f" ] && [ "$f" != "${since:-}" ] && jq -e --arg t "$2" 'select(.type==$t)' "$f" >/dev/null 2>&1 && return 0
  done
  fail=1
  return 1
}
launch() {  # simulator, then VAR=value pairs for SIMCTL_CHILD_*
  local sim=$1; shift
  xcrun simctl terminate "$sim" "$BUNDLE" 2>/dev/null || true
  since=$(newest_log "$sim")
  env SIMCTL_CHILD_SWING_SYNC_DIR="$SYNC" "${@/#/SIMCTL_CHILD_}" xcrun simctl launch "$sim" "$BUNDLE" >/dev/null
}
file_sets() { jq '[.[] | select(.source.byHand == null)] | length' "$(docs "$1")/recents/index.json" 2>/dev/null || echo 0; }

# A phone simulator with no sets yet (a fresh one, kept apart from the pipeline's "iPhone 17") analyzes one clip
# first, so there is something to mirror.
SAMPLES=${SAMPLES:-$HOME/tmp/agent/swing-samples}
if [ "$(file_sets "$PHONE")" -eq 0 ]; then
  launch "$PHONE" "SWING_VIDEO=$SAMPLES/swing-sample-4reps.mp4"
  wait_for "$PHONE" analyzed 120 || echo "      (timed out waiting for the seed clip's analysis)"
  sleep 3
fi
# Step 1: the phone mirrors.
launch "$PHONE"
wait_for "$PHONE" sync_mirrored 60 || echo "      (timed out waiting for the phone's mirror)"
phone_sets=$(file_sets "$PHONE")
phone_device=$(jq -r 'select(.type=="sync_container") | .device' "$(newest_log "$PHONE")" | tail -1)
# Step 2: the iPad reads, with the pictures.
launch "$IPAD"
wait_for "$IPAD" sync_read 90 || echo "      (timed out waiting for the iPad's read)"
sleep 5
ipad_sets=$(file_sets "$IPAD")
if [ "$phone_sets" -gt 0 ] && [ "$ipad_sets" -ge "$phone_sets" ] &&
  jq -se '([.[] | select(.type=="sync_read")][0] | .added > 0 and .files > 0)' "$(newest_log "$IPAD")" >/dev/null; then
  echo "ok    sync_read: the iPad has the phone's $phone_sets sets with their files"
else echo "FAIL  sync_read: phone=$phone_sets ipad=$ipad_sets"; fail=1; fi
# Step 4a: a bell weight set on the iPad reaches the phone, and the set is the iPad's from then on.
newest=$(jq -r '.[0].id' "$(docs "$IPAD")/recents/index.json")
launch "$IPAD" "SWING_OPEN_RECENT=$newest" "SWING_SET_BELL_KG=24"
wait_for "$IPAD" set_bell_kg 60 || echo "      (timed out waiting for the iPad's bell weight)"
sleep 12  # the iPad mirrors the row; the phone polls every 5 s
kg=$(jq -r --arg id "$newest" '.[] | select(.id==$id) | .bellKg' "$(docs "$PHONE")/recents/index.json")
owner=$(jq -r --arg id "$newest" '.[] | select(.id==$id) | .device' "$(docs "$PHONE")/recents/index.json")
if [ "$kg" = "24" ] && [ "$owner" != "$phone_device" ] && [ "$owner" != "null" ]; then
  echo "ok    sync_edit: the bell weight set on the iPad is on the phone, the set now the iPad's"
else echo "FAIL  sync_edit: kg=$kg owner=$owner phone=$phone_device"; fail=1; fi
# Step 4b: a set deleted on the iPad goes from the phone too.
launch "$IPAD" "SWING_OPEN_RECENT=$newest" "SWING_DELETE_SET=confirm"
wait_for "$IPAD" set_deleted 60 || echo "      (timed out waiting for the iPad's delete)"
sleep 12
if ! jq -e --arg id "$newest" 'any(.[]; .id==$id)' "$(docs "$PHONE")/recents/index.json" >/dev/null &&
  [ -f "$SYNC/Documents/sets/$newest/deleted.json" ]; then
  echo "ok    sync_delete: the set deleted on the iPad is gone from the phone, its tombstone in the container"
else echo "FAIL  sync_delete: $newest still on the phone or no tombstone"; fail=1; fi
for sim in "$PHONE" "$IPAD"; do xcrun simctl terminate "$sim" "$BUNDLE" 2>/dev/null || true; done
echo "sync folder: $SYNC"
exit $fail
