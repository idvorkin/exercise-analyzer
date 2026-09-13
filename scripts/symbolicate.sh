#!/usr/bin/env bash
# Symbolicates a MetricKit crash JSON (Documents/crashes/*.json, pulled by `just pull-logs`) against the app's dSYM
# from the last `just build-device`. Prints each crashed thread's frames as "binary symbol + offset".
# Usage: scripts/symbolicate.sh ~/tmp/agent/swing-logs/crashes/<stamp>.json
set -euo pipefail
FILE=$1
DSYM=$(find Build/Build/Products/Debug-iphoneos -name "ExerciseAnalyzer.app.dSYM" -maxdepth 1 | head -1)
[ -n "$DSYM" ] || { echo "no dSYM under Build/Build/Products/Debug-iphoneos: run just build-device" >&2; exit 1; }
BIN="$DSYM/Contents/Resources/DWARF/ExerciseAnalyzer"
APP_UUID=$(dwarfdump --uuid "$BIN" | awk '{print $2}' | head -1)
echo "app dSYM $APP_UUID"
jq -r --arg uuid "$APP_UUID" '
  .crashDiagnostics[]? |
  "crash: exceptionType \(.diagnosticMetaData.exceptionType // "-") signal \(.diagnosticMetaData.signal // "-") reason \(.diagnosticMetaData.terminationReason // "-")",
  (.callStackTree.callStacks[] | select(.threadAttributed == true) | .. | objects | select(has("address")) |
    "\(.binaryName // "?") \(.binaryUUID // "?") \(.address) \(.offsetIntoBinaryTextSegment // 0)")' "$FILE" |
while IFS= read -r line; do
  case "$line" in
    crash:*) echo "$line" ;;
    *)
      set -- $line
      name=$1; uuid=$2; addr=$3; off=$4
      if [ "$(echo "$uuid" | tr a-z A-Z)" = "$(echo "$APP_UUID" | tr a-z A-Z)" ]; then
        sym=$(atos -o "$BIN" -arch arm64 -l 0x0 "$(printf '0x%x' "$off")" 2>/dev/null || true)
        echo "  $name  $sym"
      else
        echo "  $name  +$off (system)"
      fi
      ;;
  esac
done
