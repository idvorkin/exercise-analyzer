#!/usr/bin/env bash
# Fetch the yolo26n-pose Core ML package the app bundles (gitignored) from the Ultralytics release.
set -euo pipefail
cd "$(dirname "$0")/.."
MODEL=yolo26n-pose
DEST=ExerciseAnalyzer/$MODEL.mlpackage
if [ -d "$DEST" ]; then echo "$DEST already present"; exit 0; fi
TMP=$(mktemp -d)
curl -sSL -o "$TMP/$MODEL.zip" "https://github.com/ultralytics/yolo-ios-app/releases/download/v8.3.0/$MODEL.mlpackage.zip"
unzip -q "$TMP/$MODEL.zip" -d "$TMP"
FOUND=$(find "$TMP" -name "$MODEL.mlpackage" -type d | head -1)
mv "$FOUND" "$DEST"
rm -rf "$TMP"
echo "installed $DEST"
