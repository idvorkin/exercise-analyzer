#!/usr/bin/env bash
# Files each shake-to-report bug from the phone's bugs.jsonl as a GitHub issue, once.
# Each issue body carries a `<!-- bug:<reported_at> -->` marker; reports whose marker already exists are skipped.
# Usage: scripts/file-bugs.sh [path/to/bugs.jsonl]   (default: ~/tmp/agent/swing-logs/bugs.jsonl, see `just pull-logs`)
set -euo pipefail
REPO="${REPO:-idvorkin/exercise-analyzer}"
BUGS="${1:-$HOME/tmp/agent/swing-logs/bugs.jsonl}"
[ -f "$BUGS" ] || { echo "no bug file at $BUGS" >&2; exit 1; }

existing=$(gh issue list -R "$REPO" --state all --limit 500 --json body --jq '.[].body' | grep -o 'bug:[0-9TZ:-]*' || true)

while IFS= read -r line; do
  [ -n "$line" ] || continue
  at=$(jq -r '.reported_at' <<<"$line")
  if grep -q "bug:$at" <<<"$existing"; then echo "skip  $at (already filed)"; continue; fi
  note=$(jq -r '.note' <<<"$line")
  title=$(printf '%s' "$note" | sed -e 's/^[-* ]*//' | head -1 | cut -c1-80)
  body=$(jq -r '
    "**Report from the phone** (shake to report), " + .reported_at + "\n\n" +
    "> " + (.note | gsub("\n"; "\n> ")) + "\n\n" +
    "| | |\n|---|---|\n" +
    "| Clip | `" + (.clip // "–") + "` |\n" +
    "| Exercise | " + (.exercise // "–") + " |\n" +
    "| Playhead | " + (.playhead // "–") + " |\n" +
    "| Log | `" + (.log // "–") + "` (pull with `just pull-logs`) |\n\n" +
    "<!-- bug:" + .reported_at + " -->"' <<<"$line")
  url=$(gh issue create -R "$REPO" --title "$title" --body "$body" --label bug)
  echo "filed $at → $url"
done <"$BUGS"
