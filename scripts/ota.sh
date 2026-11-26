#!/usr/bin/env bash
# `just ota`: this checkout's commit, development-signed, on the Cockpit's /builds page, from where the iPhone and the
# iPad install it over the air (story 089 in docs/stories/06-feedback.md; the shape of Context Grabber's `just ota`).
# Archives the app in Release (the watch app inside it), exports it signed for development (method `debugging`), checks
# the pose model is in the bundle, and copies it to the Cockpit as ea-<sha8>.ipa. The Cockpit writes the install
# manifest itself from the ipa's Info.plist, so only the ipa goes.
# It takes build.lock and xcode-signing.lock itself; never run it under them (lockf would wait forever on its own lock).
#
# Usage: ota.sh [--dry-run] [--force]
#   --dry-run  the plan: the commit, the archive, the destination; builds, signs and copies nothing
#   --force    copy even when /builds already has ea-<sha8>.ipa (otherwise it is only touched, so it sorts newest)
#
# Environment: OTA_HOST (developer@c-5004) and OTA_DIR (gits/igor2/cockpit-data/builds), where the package goes.
# Exits: 0 built and copied (or already there); 1 the package could not be read; 64 usage; 65 the checkout has
# uncommitted changes; 66 no pose model (just model); 78 a person must act (the Xcode account); 80 the Mac stayed
# locked (BugKit's guard); a failed build's own code otherwise.
set -uo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd) || exit 1
cd "$repo" || exit 1

dry_run=0 force=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --force) force=1 ;;
    -h | --help)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "ota: unknown argument $1 (--help)" >&2
      exit 64
      ;;
  esac
  shift
done

host=${OTA_HOST:-developer@c-5004}
dir=${OTA_DIR:-gits/igor2/cockpit-data/builds}
sha=$(git rev-parse --short=8 HEAD) || exit 1
describe=$(git describe --always --dirty --exclude='*') || exit 1
name=ea-$sha
archive=Build/Archives/$name.xcarchive
out=Build/Export/$name-dev
published="$dir/$name.ipa"

[ -d ExerciseAnalyzer/yolo26n-pose.mlpackage ] || {
  echo "ota: no ExerciseAnalyzer/yolo26n-pose.mlpackage: run just model first (it is gitignored, and a slot has none)" >&2
  exit 66
}
if [ "$dry_run" = 1 ]; then
  echo "ota: dry run: $describe"
  echo "  archive: $archive (Release, generic iOS)"
  echo "  export:  $out, development-signed"
  echo "  check:   yolo26n-pose.mlmodelc in the bundle"
  echo "  copy:    $host:$published"
  exit 0
fi
case $describe in *-dirty)
  echo "ota: the checkout has uncommitted changes; commit or stash them (the package is named by its commit)" >&2
  exit 65
  ;;
esac

remote=(ssh -o BatchMode=yes -o ConnectTimeout=15 -- "$host")
q() { printf "'%s'" "${1//\'/\'\"\'\"\'}"; }
if [ "$force" = 0 ] && "${remote[@]}" "test -f $(q "$published")" 2>/dev/null; then
  "${remote[@]}" "touch $(q "$published")" || true
  echo "ota: $host:$published already there (touched, so it is the newest); --force copies again"
  exit 0
fi

team=$(sed -n 's/.*DEVELOPMENT_TEAM = \([A-Z0-9]*\);.*/\1/p' ExerciseAnalyzer.xcodeproj/project.pbxproj | head -1)
kit=$(scripts/bugkit-path.sh) || exit 2
mkdir -p Build/Archives "$HOME/tmp/agent/locks"
t0=$(date +%s)
# The repo's rule: the whole signing build under build.lock and xcode-signing.lock, the guard inside.
echo "ota: archiving $describe (Build/ota-archive.log)"
lockf -k "$HOME/tmp/agent/locks/build.lock" lockf -k "$HOME/tmp/agent/locks/xcode-signing.lock" \
  "$kit/scripts/signing-guard.sh" xcodebuild -project ExerciseAnalyzer.xcodeproj -scheme ExerciseAnalyzer \
  -configuration Release -destination generic/platform=iOS -derivedDataPath Build/ -archivePath "$archive" \
  -allowProvisioningUpdates BUGKIT_COMMIT="$describe" archive >Build/ota-archive.log 2>&1
rc=$?
grep -E 'error:' Build/ota-archive.log | sort -u | head -20 >&2
[ "$rc" -eq 0 ] || { echo "ota: archive failed ($rc; 78: the Xcode account, stop and tell Igor)" >&2; exit "$rc"; }
grep -q "ARCHIVE SUCCEEDED" Build/ota-archive.log || { echo "ota: no ARCHIVE SUCCEEDED in Build/ota-archive.log" >&2; exit 1; }
t1=$(date +%s)

rm -rf "$out" && mkdir -p "$out"
cat >"$out/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>debugging</string>
	<key>signingStyle</key><string>automatic</string>
	<key>teamID</key><string>$team</string>
	<key>thinning</key><string>&lt;none&gt;</string>
</dict>
</plist>
EOF
echo "ota: exporting development-signed (Build/ota-export.log)"
lockf -k "$HOME/tmp/agent/locks/xcode-signing.lock" "$kit/scripts/signing-guard.sh" \
  xcodebuild -exportArchive -archivePath "$archive" -exportPath "$out" -exportOptionsPlist "$out/ExportOptions.plist" \
  -allowProvisioningUpdates >Build/ota-export.log 2>&1
rc=$?
[ "$rc" -eq 0 ] && grep -q "EXPORT SUCCEEDED" Build/ota-export.log || {
  tail -20 Build/ota-export.log >&2
  echo "ota: export failed ($rc)" >&2
  exit $((rc == 0 ? 1 : rc))
}
ipa=$out/ExerciseAnalyzer.ipa
[ -f "$ipa" ] || { echo "ota: the export left no $ipa" >&2; exit 1; }
t2=$(date +%s)

# What the package holds, read back rather than assumed: the model compiled in, and the commit.
"$repo/scripts/ipa-has-model.sh" "$ipa"
case $? in
  0) ;;
  1)
    echo "ota: $ipa has no yolo26n-pose.mlmodelc; nothing copied" >&2
    exit 66
    ;;
  *)
    echo "ota: $ipa could not be listed; nothing copied" >&2
    exit 1
    ;;
esac
plist=$(mktemp) || exit 1
trap 'rm -f "$plist"' EXIT
unzip -p "$ipa" Payload/ExerciseAnalyzer.app/Info.plist >"$plist" || exit 1
commit=$(plutil -extract BugKitCommit raw "$plist") || exit 1
[ "$(git rev-parse --verify "$commit^{commit}" 2>/dev/null)" = "$(git rev-parse HEAD)" ] || {
  echo "ota: the package says it is $commit, not $sha; nothing copied" >&2
  exit 1
}
sum=$(shasum -a 256 "$ipa" | cut -c1-16)

stage="$dir/.$name.ipa.$$.$RANDOM.part"
scp -q -o BatchMode=yes -o ConnectTimeout=15 -- "$ipa" "$host:$stage" &&
  "${remote[@]}" "mv -f -- $(q "$stage") $(q "$published")" || {
  rc=$?
  "${remote[@]}" "rm -f -- $(q "$stage")" >/dev/null 2>&1 || :
  echo "ota: the copy to $host:$published failed; the package is at $ipa" >&2
  exit "$rc"
}
t3=$(date +%s)
echo "ota: $name -> $host:$published (sha256 $sum)"
echo "ota: times: archive $((t1 - t0)) s, export $((t2 - t1)) s, copy $((t3 - t2)) s"
