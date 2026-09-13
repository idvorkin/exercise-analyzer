#!/usr/bin/env bash
# Publishes the kettlebell detector package as a GitHub release asset so scripts/download-model.sh can fetch it.
# Run by a human (an agent cannot create releases here). Idempotent: an existing release gets the asset replaced.
# Usage: scripts/publish-models.sh [path/to/yoloe-26n-kettlebell.mlpackage]
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=${REPO:-idvorkin/exercise-analyzer}
TAG=${TAG:-models-2026-09-12}
PKG=${1:-ExerciseAnalyzer/yoloe-26n-kettlebell.mlpackage}
[ -d "$PKG" ] || { echo "no package at $PKG (run scripts/model-trials/export_bell_detector.py yoloe 26n and copy it there)" >&2; exit 1; }
NAME=$(basename "$PKG")
TMP=$(mktemp -d)
(cd "$(dirname "$PKG")" && zip -qr "$TMP/$NAME.zip" "$NAME")
if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" "$TMP/$NAME.zip" -R "$REPO" --clobber
else
  gh release create "$TAG" "$TMP/$NAME.zip" -R "$REPO" --title "Models $TAG: YOLOE nano kettlebell detector" \
    --notes "$NAME: YOLOE 26 nano exported to Core ML (640 px, fp16, NMS inside) with the single text prompt \"kettlebell\" by scripts/model-trials/export_bell_detector.py yoloe 26n. Fetched by scripts/download-model.sh. Trial and plumbing notes: docs/analysis/kettlebell-detector.md."
fi
rm -rf "$TMP"
echo "published $NAME to $REPO release $TAG"
