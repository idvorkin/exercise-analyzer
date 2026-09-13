#!/usr/bin/env bash
# Event stream for an agent Monitor: polls the phone's bugs.jsonl through bugs-check.sh and prints one line per
# report that is not yet an issue, each report once. Silent while nothing is new, so the agent is woken only when
# there is something to file (cheaper than a /loop that runs the model every few minutes to look).
# Usage: scripts/bugs-monitor.sh [device udid] [poll seconds, default 60]
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
DEVICE=${1:-00008150-000A31D10CF2401C}
EVERY=${2:-60}
seen=" "
while true; do
  out=$("$HERE/bugs-check.sh" "$DEVICE" 2>/dev/null || true)
  while IFS= read -r line; do
    case "$line" in
      new:*)
        at=$(awk '{print $2}' <<<"$line")
        case "$seen" in *" $at "*) ;; *) seen="$seen$at "; echo "$line" ;; esac
        ;;
    esac
  done <<<"$out"
  sleep "$EVERY"
done
