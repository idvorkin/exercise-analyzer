#!/usr/bin/env bash
# Fetch the Core ML packages the app bundles (gitignored): the yolo26n-pose model from the Ultralytics release and
# the YOLOE nano kettlebell detector (#18) from this repo's models release. Either one already present is kept.
set -euo pipefail
cd "$(dirname "$0")/.."

fetch() {  # name url
  local dest="ExerciseAnalyzer/$1.mlpackage"
  if [ -d "$dest" ]; then echo "$dest already present"; return; fi
  local tmp; tmp=$(mktemp -d)
  curl -sSL -o "$tmp/$1.zip" "$2"
  unzip -q "$tmp/$1.zip" -d "$tmp"
  local found; found=$(find "$tmp" -name "$1.mlpackage" -type d | head -1)
  [ -n "$found" ] || { echo "no $1.mlpackage inside $2" >&2; rm -rf "$tmp"; return 1; }
  mv "$found" "$dest"
  rm -rf "$tmp"
  echo "installed $dest"
}

fetch yolo26n-pose "https://github.com/ultralytics/yolo-ios-app/releases/download/v8.3.0/yolo26n-pose.mlpackage.zip"
# The detector is exported by scripts/model-trials/export_bell_detector.py yoloe 26n and published as a release
# asset; without it the app runs with no bells.
fetch yoloe-26n-kettlebell "https://github.com/idvorkin/exercise-analyzer/releases/download/models-2026-09-12/yoloe-26n-kettlebell.mlpackage.zip" \
  || echo "kettlebell detector not fetched: publish the models-2026-09-12 release or run scripts/model-trials/export_bell_detector.py yoloe 26n and copy the package into ExerciseAnalyzer/"
