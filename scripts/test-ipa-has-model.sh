#!/usr/bin/env bash
# Checks scripts/ipa-has-model.sh (ea-cvy): an ipa whose listing is far bigger than a pipe's buffer, with the model
# listed early, is found (the old `unzip -l | grep -q` under pipefail refused it); one without the model is not;
# a file that is not a zip is an error, not "no model". Part of `just test`.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd) || exit 1
check="$here/ipa-has-model.sh"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
fail=0

app="$tmp/with/Payload/ExerciseAnalyzer.app"
mkdir -p "$app/yolo26n-pose.mlmodelc" "$app/zz" "$tmp/without/Payload/ExerciseAnalyzer.app"
echo model >"$app/yolo26n-pose.mlmodelc/model.mil"
# ~4,000 names of ~80 bytes: a listing of ~300 KB, several pipe buffers past the model's line.
for i in $(seq 1 4000); do : >"$app/zz/a-file-name-long-enough-to-fill-the-pipe-$i.txt"; done
echo plist >"$tmp/without/Payload/ExerciseAnalyzer.app/Info.plist"
(cd "$tmp/with" && zip -qr0 "$tmp/with.ipa" Payload) || exit 1
(cd "$tmp/without" && zip -qr0 "$tmp/without.ipa" Payload) || exit 1
echo "not a zip" >"$tmp/broken.ipa"

expect() {
  local want=$1 ipa=$2 got
  "$check" "$ipa" 2>/dev/null
  got=$?
  if [ "$got" -eq "$want" ]; then echo "ipa-has-model: $(basename "$ipa") exits $got, passed"; else
    echo "ipa-has-model: $(basename "$ipa") exits $got, wanted $want, failed" >&2
    fail=1
  fi
}
expect 0 "$tmp/with.ipa"
expect 1 "$tmp/without.ipa"
expect 2 "$tmp/broken.ipa"
exit $fail
