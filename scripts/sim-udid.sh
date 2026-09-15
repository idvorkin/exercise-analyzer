#!/usr/bin/env bash
# Prints the UDID of the simulator named $1 on the newest available runtime, or $1 itself when it is already a
# UDID. `simctl` addresses devices by name, and every Xcode update leaves a second "iPhone 17" on the older
# runtime behind: a boot by name and a launch by name can then land on different devices (Xcode 27, 2026-09-15).
# Usage: scripts/sim-udid.sh "iPhone 17"
set -euo pipefail
name=${1:?simulator name or UDID}
if [[ "$name" =~ ^[0-9A-Fa-f-]{36}$ ]]; then echo "$name"; exit 0; fi
# The listing groups devices under "-- <runtime> --" headers in ascending version order; the last match wins.
udid=$(xcrun simctl list devices available | grep -F -- "    $name (" | tail -1 | grep -oE "[0-9A-F-]{36}" | head -1 || true)
if [ -z "$udid" ]; then
  echo "FAIL  no available simulator named '$name' (xcrun simctl list devices available)" >&2
  exit 1
fi
echo "$udid"
