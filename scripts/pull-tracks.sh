#!/usr/bin/env bash
# Archives every pose track the phone holds (Documents/recents/<id>/analysis.json) as a compact fixture under
# ExerciseCore/Tests/ExerciseCoreTests/Fixtures/tracks/, so any set can become a known-answer test later and the
# archive report (swift test --filter ArchivedTracks) shows how every set counts under the current analyzers.
# Usage: scripts/pull-tracks.sh [device udid]
set -euo pipefail
DEVICE=${1:-00008150-000A31D10CF2401C}
BUNDLE=com.idvorkin.exerciseanalyzer
STAGE=$HOME/tmp/agent/swing-logs/phone/Documents/recents
OUT=ExerciseCore/Tests/ExerciseCoreTests/Fixtures/tracks
mkdir -p "$STAGE" "$OUT"
xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer --domain-identifier $BUNDLE \
  --source Documents/recents --destination "$STAGE" 2>&1 | grep -E "received|rror" | grep -v provisioning || true
python3 - "$STAGE" "$OUT" <<'PY'
import json, pathlib, sys, datetime
stage, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
index = {e["id"]: e for e in json.load(open(stage / "index.json"))} if (stage / "index.json").exists() else {}
written = 0
for snap in sorted(stage.glob("*/analysis.json")):
    entry_id = snap.parent.name
    meta = index.get(entry_id, {})
    d = json.load(open(snap))
    exercise = d.get("exercise") or meta.get("exercise") or "unknown"
    stamp = meta.get("recordedAt") or meta.get("analyzedAt")
    day = datetime.datetime(2001, 1, 1) + datetime.timedelta(seconds=stamp) if stamp else None
    name = f"{exercise}-{day.strftime('%Y%m%d') if day else 'nodate'}-{entry_id[:8]}.json"
    target = out / name
    if target.exists():
        continue
    frames = [{"time": f["time"], "imageSize": f["imageSize"], "box": f.get("box"),
               "pose": ({"xyn": f["pose"]["xyn"], "conf": f["pose"]["conf"]} if f.get("pose") else None)} for f in d["frames"]]
    json.dump({"version": 1, "source": {"recents_id": entry_id, "exercise": exercise, "reps_when_saved": len(d.get("reps", []))},
               "frames": frames}, open(target, "w"), separators=(",", ":"))
    written += 1
    print(f"archived {name}: {len(frames)} frames, {len(d.get('reps', []))} reps when saved")
print(f"{written} new track(s); {len(list(out.glob('*.json')))} in the archive")
PY
