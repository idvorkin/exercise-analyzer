# Test architecture

The rule: every question is answered on the cheapest rung that can answer it, and a fix is not "done" until the
rung that can see it has seen it. The rungs are ordered by cost, and the split follows the code: the platform-free
analysis lives in the `ExerciseCore` package so it can run on the Mac; only what genuinely needs AVFoundation, a
camera, a display, or a wrist goes higher.

| Rung | What runs | Command | Time | Answers |
|---|---|---|---|---|
| 1 Host | `ExerciseCore` XCTest against stored pose tracks | `just test` | ~1 s | detection, rep counts, phases, checkpoints, quality, crops, frame status, message types |
| 1.5 Mac model | `posetrack`: the pose model plus the analyzers on a clip | `just analyze clip.mov` | ~clip length ÷ 4 | what the phone would count for any clip on the Mac (AirDropped or sample); makes fixtures without the phone |
| 2 Simulator | the app, driven by env hooks, judged from its log | `just test-sim` | 5–8 min | loading, offline pose pass, analysis in the app, trim (`AVAssetExportSession`), player start, Recents |
| 3 Phone | the app on the iPhone, a human at the gym | `just run-device` then `just pull-logs` | minutes + a person | Neural Engine speed, camera and recorder, HDR playback, Photos, the watch, everything visual |

## What kind of test goes where

| Change | Where it must be verified | How |
|---|---|---|
| Analyzer thresholds, phase logic, rep rules | Host | fixture count pinned in [`PoseTrackFixtures.swift`](../ExerciseCore/Tests/ExerciseCoreTests/PoseTrackFixtures.swift); trace via `TuningReports` |
| Exercise detector | Host | `DetectionTests`: every fixture must detect as its own exercise with confidence ≥ 60 |
| Skeleton geometry (angles, sides, uprightness) | Host | `SkeletonTests` with synthetic poses |
| Crop / me-view, rep span for trimming | Host | `RepCountTests.testRepSpanAndStableCropCoverTheSet` |
| In-frame status, watch messages | Host | [`FrameStatusTests.swift`](../ExerciseCore/Tests/ExerciseCoreTests/FrameStatusTests.swift) |
| Anything in `AnalysisPipeline` (re-analysis, shifting after a trim) | Host | `PoseTrackTests`, `RepCountTests` |
| Offline pose pass, import, analysis wiring in the app | Simulator | `check <clip> <exercise> <reps>` in [`sim-smoke.sh`](../scripts/sim-smoke.sh) |
| Trim (export session, keyframe alignment, player start) | Simulator, then one phone trim on an HDR clip | `check_trim` in `sim-smoke.sh`; phone: tap Done after a recording, read `trim`/`display_frame` events |
| Player, overlay, HUD, gallery layout | Simulator screenshots, then phone | [`screenshots.sh`](../scripts/screenshots.sh) for the eye; the phone for HDR and real frames |
| Camera, recorder, camera switch, idle timer | Phone only | record a set, `just pull-logs`, check `camera_*`, `recording_partial`, `error` events |
| HDR washout, EDR, layer transforms | Phone only | `video_track` (`hdr`, `edr_headroom`) and `player_layer` events; the eye |
| Apple Watch companion | Phone + watch | `watch_session`, `watch_reachable`, `ui` events with `from: watch` |
| Audio never interrupted | Phone only | play music, record, listen |

Bugs in analysis are reproduced on the host first, never tuned on the phone: export the set as a fixture (below),
make the failing count fail in `swift test`, fix, then ship.

## Rung 1: host tests

Package: [`ExerciseCore`](../ExerciseCore). `cd ExerciseCore && swift test`, or `just test`.

**Fixtures** are compact pose tracks in
[`ExerciseCore/Tests/ExerciseCoreTests/Fixtures/`](../ExerciseCore/Tests/ExerciseCoreTests/Fixtures/):
`{version: 1, frames: [{time, imageSize: [w, h], box, pose: {xyn, conf}}]}`, COCO-17 keypoints normalized to the
image. Each is registered in `Fixture.all` with the exercise, the expected rep count, and `humanVerified`
(Igor confirmed the count) versus a regression baseline (the count the analyzer produced when the fixture was cut).

To make a fixture from a set on the phone:

```bash
just pull-logs                      # find the Recents id in the log's recents_saved event
xcrun devicectl device copy from --device <udid> --domain-type appDataContainer \
  --domain-identifier com.idvorkin.exerciseanalyzer \
  --source Documents/recents/<id> --destination ~/tmp/agent/swing-logs/phone/Documents/recents/<id>
```

then convert `analysis.json` (AnalysisSnapshot v2: `frames[].pose.xyn/conf`, `frames[].box`) to the compact form
and drop it in `Fixtures/`. The snapshot holds every frame the offline pass produced, so the fixture is exactly what
the phone analyzed.

**Test classes** ([`ExerciseCoreTests.swift`](../ExerciseCore/Tests/ExerciseCoreTests/ExerciseCoreTests.swift)):

- `DetectionTests`: every fixture detects as its exercise; swing detection survives mirroring.
- `RepCountTests`: every fixture counts its reps, every rep has every phase position and a 0–100 score; swing
  counts and lockout angles match when mirrored; rep span and stable crop cover the 9-rep clip.
- `SkeletonTests`: spine/arm/knee angle math on synthetic poses.
- `PoseTrackTests`: nearest-frame lookup and shifting after a trim.
- `FrameStatusTests`: in frame / clipped edges / coverage and the watch message round trip.

**Tuning reports** ([`TuningReports.swift`](../ExerciseCore/Tests/ExerciseCoreTests/TuningReports.swift)) are not
assertions. `swift test --filter TuningReports` prints, per fixture, every phase transition an analyzer took (its
`trace` hook), each rep's checkpoint times and quality, raw per-second signals, and the count under alternative
thresholds. This is how an analyzer gets tuned against a bad set, and how a "why did it count that" question gets
answered with numbers instead of theories.

## Rung 1.5: the model on the Mac

[`ExerciseCore/Sources/posetrack/main.swift`](../ExerciseCore/Sources/posetrack/main.swift) is a macOS executable
in the package: `just analyze <clip> [--exercise kind] [--fixture out.json]`. It reads the clip through the same
rotation-applying video composition as the app, letterboxes with Vision's `scaleFit` like the SDK, maps the
end2end output back with the SDK's letterbox math, and runs the detector and analyzers from `ExerciseCore`. On an
M4 it runs at 130 fps or more (the simulator does 20). Poses match the phone's to a few pixels (3 px mean on the 4-rep sample), so `--fixture`
writes a host-test fixture from any clip: this is how a clip that only exists on the Mac (AirDrop, a sample) gets
into rung 1. The model comes from `just model` (`ExerciseAnalyzer/yolo26n-pose.mlpackage`, gitignored) and is
compiled once into `~/tmp/agent/skill/posetrack/`.

## Rung 2: simulator smoke

[`scripts/sim-smoke.sh`](../scripts/sim-smoke.sh), run by `just test-sim` after `just build-sim`.

The simulator cannot be tapped from a script, so the app has **launch hooks** read from the environment
(pass them through `simctl` as `SIMCTL_CHILD_<name>`):

| Hook | Effect |
|---|---|
| `SWING_VIDEO=/path.mp4` | load the clip on launch (waits for the model) |
| `SWING_AUTO_TRIM=1` | trim to the rep span right after the first analysis |
| `SWING_UNDO_TRIM=1` | undo that trim 3 s later (with `SWING_AUTO_TRIM`) |
| `SWING_OPEN_RECENT=1` | reopen the newest Recents entry |
| `SWING_BUG=text` | file a bug report on launch |
| `SWING_SHOW_WORKOUTS=1` | open the workout gallery on launch (screenshots) |
| `SWING_PHOTOS_ACCESS=1` | ask for Photos access when the gallery opens (the simulator cannot be granted Photos access from the command line on iOS 26, so this dialog needs a hand) |

Results are read from the **session log** (`Documents/logs/*.jsonl` in the app container), not the screen. The
simulator runs the pose model on the CPU at roughly 20 fps, a tenth of the phone, so the script waits for the
`analyzed` or `trim` event (`wait_for`) instead of sleeping a fixed time. `ONLY=trim just test-sim` runs one check.

Checks today: three clips must detect and count (4 swings, 6 pistols, 8 Bulgarian); the trim check auto-trims the
9-rep clip and asserts a lossless passthrough cut that starts on a keyframe within 1.5 s of the requested start and
a first displayed frame at time zero.

Sample clips live outside the repo in `~/tmp/agent/swing-samples/` (`$SAMPLES`); sources are listed in the README.

**Screenshots** for the README come from the same machinery:
[`scripts/screenshots.sh`](../scripts/screenshots.sh) presets view modes through user defaults (`overlayMode`,
`meView`, `galleryHeight`), launches each clip, waits for `analyzed`, and captures with `simctl io screenshot`.

## Rung 3: phone

`just run-device` builds with automatic signing (the sandbox must be off for provisioning), installs with
`devicectl`, and launches (fails harmlessly if the phone is locked). Then a person uses the app, and
`just pull-logs` brings back the logs and bug reports.

What only the phone can show: the Neural Engine (offline pass at 100–190 fps), the camera path
(`CameraSource`, `FrameRecorder`, camera switch, idle timer), HDR playback (`video_track.hdr`,
`edr_headroom`; never transform or clip an `AVPlayerLayer` ancestor), Photos in-place import, audio mixing, and the
watch.

**Log before theorizing.** When a phone symptom is unexplained, the first change is a log event, not a fix. The
log carries per-frame metrics, every phase transition, reps, detection reasons, seeks (which control asked, player
time before and after), trims (requested and aligned start, passthrough or re-encode), camera events, watch
session state, and bug reports. `just log-summary <file>` prints everything except per-frame events.

## Bug flow

Shake the phone → `bug_report` event + `Documents/bugs.jsonl` → `just pull-logs` → `just file-bugs` files each new
report as a GitHub issue once (marker `<!-- bug:<reported_at> -->`) → analysis and evidence go on the issue as a
comment → one commit per issue with a closing keyword (`Fixes #N`) once the right rung has verified it.
