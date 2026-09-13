#!/usr/bin/env bash
# Quick dirty check (issue #26): copies only bugs.jsonl from the phone and counts reports not yet filed as issues.
# Exit 1 when there are new reports (so a loop or a prompt can tell at a glance), 0 when clean.
set -euo pipefail
DEVICE=${1:-00008150-000A31D10CF2401C}
REPO=${REPO:-idvorkin/exercise-analyzer}
OUT=$HOME/tmp/agent/swing-logs/bugs.jsonl
mkdir -p "$(dirname "$OUT")"
if ! xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer --domain-identifier com.idvorkin.exerciseanalyzer \
  --source Documents/bugs.jsonl --destination "$OUT" >/dev/null 2>&1; then
  echo "phone not reachable"; exit 0
fi
filed=$(gh issue list -R "$REPO" --state all --limit 500 --json body --jq '.[].body' | grep -o 'bug:[0-9TZ:-]*' || true)
new=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  at=$(jq -r '.reported_at' <<<"$line")
  grep -q "bug:$at" <<<"$filed" || { new=$((new + 1)); echo "new: $at  $(jq -r '.note' <<<"$line" | head -1 | cut -c1-90)"; }
done <"$OUT"
if [ "$new" -gt 0 ]; then echo "$new new bug report(s): run just pull-logs && just file-bugs"; exit 1; fi
echo "no new bug reports"
