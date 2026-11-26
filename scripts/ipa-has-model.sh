#!/usr/bin/env bash
# Exits 0 when the ipa holds the compiled pose model (story 089; `just ota` checks every package with it), 1 when it
# does not, 2 when the ipa cannot be read.
# The listing is read whole before it is searched: `unzip -l | grep -q` under pipefail failed on an ipa that held
# the model, because grep -q stops at the first match and unzip dies of SIGPIPE (ea-cvy, ea-ed5548c3 refused).
#
# Usage: ipa-has-model.sh <ipa>
set -uo pipefail
[ $# -eq 1 ] || { echo "usage: ipa-has-model.sh <ipa>" >&2; exit 64; }
listing=$(unzip -Z1 "$1") || exit 2
grep -q '^Payload/ExerciseAnalyzer.app/yolo26n-pose.mlmodelc/' <<<"$listing"
