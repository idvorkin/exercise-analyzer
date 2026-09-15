#!/usr/bin/env bash
# Archives every pose track the phone holds (Documents/recents/<id>/analysis.json) as a compact fixture under
# ExerciseCore/Tests/ExerciseCoreTests/Fixtures/tracks/, so any set can become a known-answer test later and the
# archive report (swift test --filter ArchivedTracks) shows how every set counts under the current analyzers.
# Usage: scripts/pull-tracks.sh [device udid]
# The archive is keyed by entry id, not by date: a file already holding an id keeps it under whatever date
# prefix, so a re-pull refreshes it in place (renamed to the dated name once the phone's index carries a date)
# instead of leaving a second file beside it. Two different sets cannot share an 8-character id prefix by
# accident; when the same id arrives with a different exercise (one clip re-analyzed as another exercise), the
# newer analysis wins and the older file is renamed to <name>-superseded[.N].json, never left beside it under
# the id key and never deleted.
# PULL_TRACKS_STAGE / PULL_TRACKS_OUT override the phone staging dir and the archive dir when testing this script.
set -euo pipefail
DEVICE=${1:-00008150-000A31D10CF2401C}
BUNDLE=com.idvorkin.exerciseanalyzer
STAGE=${PULL_TRACKS_STAGE:-$HOME/tmp/agent/swing-logs/phone/Documents/recents}
OUT=${PULL_TRACKS_OUT:-ExerciseCore/Tests/ExerciseCoreTests/Fixtures/tracks}
mkdir -p "$STAGE" "$OUT"
# A failed copy (phone locked, unplugged) must stop here, or a stale stage is re-archived as if fresh.
copy_log=$(mktemp)
if ! xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer --domain-identifier $BUNDLE \
  --source Documents/recents --destination "$STAGE" >"$copy_log" 2>&1; then
  grep -E "rror" "$copy_log" | grep -v provisioning || true
  echo "FAIL  devicectl could not copy Documents/recents from the phone (locked? unplugged?)"
  exit 1
fi
grep -E "received" "$copy_log" || true
python3 - "$STAGE" "$OUT" <<'PY'
import json, pathlib, sys, datetime, re
stage, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
index = {e["id"]: e for e in json.load(open(stage / "index.json"))} if (stage / "index.json").exists() else {}

def archived_exercise(path):
    """The exercise an archive file holds: its embedded source, else its file stem."""
    try:
        return json.load(open(path))["source"].get("exercise")
    except (OSError, ValueError, KeyError, AttributeError):
        m = re.match(r"^(.*)-(?:\d{8}|nodate)-[0-9A-Fa-f]{8}\.json$", path.name)
        return m.group(1) if m else None

written = 0
for snap in sorted(stage.glob("*/analysis.json")):
    entry_id = snap.parent.name
    id8 = entry_id[:8]
    meta = index.get(entry_id, {})
    d = json.load(open(snap))
    exercise = d.get("exercise") or meta.get("exercise") or "unknown"
    stamp = meta.get("recordedAt") or meta.get("analyzedAt")
    day = datetime.datetime(2001, 1, 1) + datetime.timedelta(seconds=stamp) if stamp else None
    dated_name = f"{exercise}-{day.strftime('%Y%m%d') if day else 'nodate'}-{id8}.json"
    has_bells = any(f.get("bells") for f in d["frames"])

    # The archive key is the entry id: every file already holding it, under any date prefix.
    same_id = sorted(out.glob(f"*-{id8}.json"))
    same_exercise = [p for p in same_id if archived_exercise(p) == exercise]
    if not same_exercise:
        # A different exercise holds this id (one clip re-analyzed): the newer analysis wins.
        for old in same_id:
            dest = old.with_name(old.stem + "-superseded.json")
            n = 0
            while dest.exists():
                n += 1
                dest = old.with_name(f"{old.stem}-superseded-{n}.json")
            old.rename(dest)
            print(f"collision on {id8}: {exercise} wins, {old.name} -> {dest.name}")
        target = out / dated_name
    else:
        # One set, re-pulled: a single file. The dated name wins once a date is known.
        target = out / dated_name if day else next(
            (p for p in same_exercise if "-nodate-" not in p.name), out / dated_name)
    # An archived track is refreshed once when the phone's copy gained the detector's sightings (#50).
    if target.exists() and not (has_bells and '"bells"' not in target.read_text()):
        if not same_exercise:
            print(f"kept {target.name} (no new sightings)")
        # Consolidate same-exercise twins even when the content is kept: one file per id.
        for twin in same_exercise:
            if twin != target:
                twin.unlink()
                print(f"consolidated {twin.name} -> {target.name}")
        continue
    frames = [{"time": f["time"], "imageSize": f["imageSize"], "box": f.get("box"),
               "pose": ({"xyn": f["pose"]["xyn"], "conf": f["pose"]["conf"]} if f.get("pose") else None),
               **({"bells": f["bells"]} if f.get("bells") else {})} for f in d["frames"]]
    json.dump({"version": 1, "source": {"recents_id": entry_id, "exercise": exercise, "reps_when_saved": len(d.get("reps", []))},
               "frames": frames}, open(target, "w"), separators=(",", ":"))
    for twin in same_exercise:
        if twin != target:
            twin.unlink()
            print(f"consolidated {twin.name} -> {target.name}")
    written += 1
    print(f"archived {target.name}: {len(frames)} frames, {len(d.get('reps', []))} reps when saved")
print(f"{written} new track(s); {len(list(out.glob('*.json')))} in the archive")
PY
