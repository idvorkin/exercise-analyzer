# Test architecture

The rule: every question is answered on the cheapest rung that can answer it, and a fix is not "done" until the
rung that can see it has seen it. The rungs are ordered by cost, and the split follows the code: the platform-free
analysis lives in the `ExerciseCore` package so it can run on the Mac; only what genuinely needs AVFoundation, a
camera, a display, or a wrist goes higher.

| Rung | What runs | Command | Time | Answers |
|---|---|---|---|---|
| 1 Host | `ExerciseCore` XCTest against stored pose tracks | `just test` | ~1 s | detection, rep counts, phases, checkpoints, quality, crops, frame status, message types |
| 1.5 Mac model | `posetrack`: the pose model plus the analyzers on a clip; `scripts/model-trials/` for candidate models | `just analyze clip.mov`, `scripts/model-trials/*.py` | ~clip length ÷ 4 | what the phone would count for any clip on the Mac (AirDropped or sample); makes fixtures without the phone; whether a new model (a bell detector) works at all |
| 2 Simulator | the app, driven by env hooks, judged from its log | `just test-sim` | 5–8 min | loading, offline pose pass, analysis in the app, trim (`AVAssetExportSession`), player start, Recents |
| 2b Watch simulator | the watch app, one fixed status per state, judged by eye | `just watch-screens` | ~1 min | every watch page and button without a phone; the regression rung for #74 |
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
| Watch pages, buttons, readouts | Watch simulator | `just watch-screens`, compare each shot with the control inventory at the top of [`05-watch.md`](stories/05-watch.md) |
| Lock-screen / Control Center button | Phone only (the simulator has no lock-screen controls to press; the extension must at least build) | add the Exercise control, press it, `just pull-logs`, check `launch_control` (`action: live`) and the camera running |
| Audio never interrupted | Phone only | play music, record, listen |

Bugs in analysis are reproduced on the host first, never tuned on the phone: export the set as a fixture (below),
make the failing count fail in `swift test`, fix, then ship.

## Rung 1: host tests

Package: [`ExerciseCore`](../ExerciseCore). `cd ExerciseCore && swift test`, or `just test`.

**Fixtures** are compact pose tracks in
[`ExerciseCore/Tests/ExerciseCoreTests/Fixtures/`](../ExerciseCore/Tests/ExerciseCoreTests/Fixtures/):
`{version: 1, frames: [{time, imageSize: [w, h], box, pose: {xyn, conf}, bells}]}`, COCO-17 keypoints normalized to
the image; `bells` (optional) is every kettlebell the detector saw in the frame, `{box, conf, color: [r, g, b]}`,
from which the pipeline's tracker picks the one in play (#18). `just analyze <clip> --poses-from old.json
--fixture old.json` adds bells to an existing fixture without touching its verified poses. Each is registered in `Fixture.all` with the exercise, the expected rep count, and `humanVerified`
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

### Model trials (rung 1.5 too)

Any question about a *different* model (a detector for the bell, a bigger pose model, a new export) is answered on
the Mac with Core ML before anything touches the app: export the candidate to `.mlpackage` the way the phone
would run it, run it over the sample clips, and measure against the pose fixtures for the same clips. Scripts live
in [`scripts/model-trials/`](../scripts/model-trials/) as uv scripts (declared dependencies, run them directly):

```bash
scripts/model-trials/export_bell_detector.py world      # YOLO-World with the class "kettlebell" → Core ML
scripts/model-trials/bell_trial.py yolov8s-worldv2.mlpackage \
  ~/tmp/agent/swing-samples/swing-sample-4reps.mp4:ExerciseCore/Tests/ExerciseCoreTests/Fixtures/swing-4reps.json ...
```

A trial reports detection rate, confidence, inference time on the Mac, and, with a fixture, how far the box sits
from the nearest wrist; the numbers and the verdict go into `docs/analysis/` (the detector's file) before any app
work starts. The phone's Neural Engine timing is a separate measurement (the `offline_pass` event's
`avg_infer_ms`): the Mac says whether a model works, the phone says what it costs.

**Tracker questions run on fixtures, not video.** `swift test --filter TuningReports/testBellTrackerHeldPerFixture`
replays the stored sightings through the real tracker in a second and prints, per fixture, how often the detector
saw a bell at the hands, how often the tracker held one there, the same inside detected reps, and how the lost
frames class. A fixture for a new detector package comes from `posetrack <clip> --bell-model <pkg> --bell-conf 0.05
--fixture <out.json>` (a low floor so the replay can sweep floors), with `--poses-from <old fixture>` to keep the
poses and the rep counts; `BELL_LAB_FIXTURES=<dir>` points the report at a directory of such files.

**The proxy lies; look at frames.** "A bell within 0.2 of a wrist" also scores a rack bell behind the hands and a
ski-erg wheel, which is how a rule once showed +15 % that was all wheel (docs/analysis/kettlebell-detector.md,
2026-09-13). Before trusting any tracker gain, cut sampled frames with the tracker's bell drawn in and grade them:

```bash
cd ExerciseCore && BELL_LAB_DOTS=1 swift test --filter TuningReports/testBellTrackerHeldPerFixture | grep ^DOT > /tmp/dots.txt
scripts/model-trials/cut-dot-frames.sh /tmp/dots.txt swing-1h-9reps ~/tmp/agent/swing-samples/igor-1h-swing.mp4 25 /tmp/gt
scripts/model-trials/grade-dots.sh /tmp/gt          # Muse grades every frame headless, six at a time → labels-muse.csv
```

The grader is Igor's Muse Code contributor model (`muse exec --image`): it can look at images, it is cheap, and it
grades a frame in about fifteen seconds; the rubric is `grade-dots-rubric.txt`. It prints per clip the frames with a
bell in the hands, how many had the circle on it (recall) and how many circles sat on something else (false holds).
A human spot-check of a few frames stays worthwhile; Muse's notes column says what it saw.

## Rung 2: simulator smoke

[`scripts/sim-smoke.sh`](../scripts/sim-smoke.sh), run by `just test-sim` after `just build-sim`.

A fresh checkout or worktree needs `just model` before any app build: the `.mlpackage` binaries are gitignored
downloads, and a build without them launches with no predictor — one `model_missing` event, then silence until
every check times out (2026-09-13).

The simulator cannot be tapped from a script, so the app has **launch hooks** read from the environment
(pass them through `simctl` as `SIMCTL_CHILD_<name>`):

| Hook | Effect |
|---|---|
| `SWING_VIDEO=/path.mp4` | load the clip on launch (waits for the model) |
| `SWING_AUTO_TRIM=1` | trim to the rep span right after the first analysis |
| `SWING_UNDO_TRIM=1` | undo that trim 3 s later (with `SWING_AUTO_TRIM`) |
| `SWING_CANCEL_ANALYSIS=1` | cancel the offline pass one second in |
| `SWING_INTERRUPT_READER=<frame>` | fail the first pass at that frame with `readerFailed("Operation Interrupted")`, like a backgrounded decoder (#57) |
| `SWING_MODE=<exercise\|auto>` | switch exercise 2 s after an interrupted pass, proving a mode switch re-runs the clip (#57); launch-only, persists no default, and every smoke check resets the mode default first |
| `SWING_OPEN_RECENT=1` | reopen the newest Recents entry |
| `SWING_BUG=text` | file a bug report on launch |
| `SWING_SHOW_WORKOUTS=1` | open the workout gallery on launch (screenshots) |
| `SWING_SHOW_GALLERY=1` | open the rep gallery sheet on launch (gallery screenshots, #61) |
| `SWING_WORKOUTS_COLLAPSED=1` | open Workouts collapsed to today's summary row (with `SWING_SHOW_WORKOUTS`) |
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

Simulator names are not unique: every Xcode update leaves the previous runtime's "iPhone 17" behind, and
`simctl` by name can boot one device and launch on another. Every script resolves the name through
`scripts/sim-udid.sh` (the newest available runtime) before touching the device; pass a UDID to skip it.

## Rung 2b: the watch simulator

Every watch change runs [`scripts/watch-screens.sh`](../scripts/watch-screens.sh) (`just watch-screens`,
after `just build-sim`): it finds the watch app inside the phone build, installs it on the watch simulator,
and relaunches it once per state with `WATCH_STATE` naming a fixed status (`SIMCTL_CHILD_WATCH_STATE`, the
same launch-hook pattern as rung 2) — no phone, no pairing, no taps. Each state sleeps 3 s for first render,
then screenshots to `~/tmp/agent/sim/watch-<state>.png`. The eleven shots are compared by eye against the
control inventory at the top of [`05-watch.md`](stories/05-watch.md); a missing button is a failed rung. This
is the rung that would have caught #74 (the picture page gated on the phone being active): three watch changes
shipped on green builds and nobody saw a watch screen.

## Rung 3: phone

`just run-device` builds with automatic signing (the sandbox must be off for provisioning), installs with
`devicectl`, and launches (fails harmlessly if the phone is locked). Then a person uses the app, and
`just pull-logs` brings back the logs and bug reports.

What only the phone can show: the Neural Engine (offline pass at 100–190 fps), the camera path
(`CameraSource`, `FrameRecorder`, camera switch, idle timer), HDR playback (`video_track.hdr`,
`edr_headroom`; never transform or clip an `AVPlayerLayer` ancestor), Photos in-place import, audio mixing, and the
watch.

The watch face complication is verified only by looking at it: no simulator, no log line can show what the
face renders. Record from the watch, lower the wrist, raise it: REC, a ticking timer and the count; Done: the
final count within seconds. `watch_face` in the log proves the mirror writes behind it, not the pixels.

**Log before theorizing.** When a phone symptom is unexplained, the first change is a log event, not a fix. The
log carries per-frame metrics, every phase transition, reps, detection reasons, seeks (which control asked, player
time before and after), trims (requested and aligned start, passthrough or re-encode), camera events, watch
session state, and bug reports. `just log-summary <file>` prints everything except per-frame events.

## Bug flow

Shake the phone → `bug_report` event + `Documents/bugs.jsonl` → `just pull-logs` → `just file-bugs` files each new
report as a GitHub issue once (marker `<!-- bug:<reported_at> -->`) → analysis and evidence go on the issue as a
comment → one commit per issue with a closing keyword (`Fixes #N`) once the right rung has verified it.
