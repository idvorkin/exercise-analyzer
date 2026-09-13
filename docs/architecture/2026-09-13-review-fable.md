# Architecture review: exercise-analyzer (Fable, independent of Codex's)

Igor, this is the second opinion you asked for. Read-only, in my own worktree at 8fdf7d3, nothing built or run.
The repo is two days old (137 commits since 09-11), so "the last week" is the whole history; the numbers below
come from `git log --numstat` and reading every Swift file, the four docs, the scripts and the justfile.

---

## Summary (one page)

**Keep.** The split that matters is already right: `ExerciseCore` is platform-free, everything from a
`FrameRecord` onward (skeleton → analyzer → reps, the detector, the bell tracker, crop, span, trim shift) runs on
the Mac in a second against 11 fixtures plus 11 archived phone tracks, and the whole bell lab last night ran on
that rung. The plugin surface (`ExerciseKind` → `ExerciseDefinition` + analyzer) took the get-up in one file. The
session log as JSON Lines with the simulator scripts reading it, the shake → `bugs.jsonl` → issue marker flow,
stories carrying their own `Status:` line, and analysis notes with the numbers that decided each rule: all of
that is working and should not be touched. `OfflineAnalyzer`, `CameraSource`, `FrameRecorder`, `VideoFile`,
`SessionLog`, `WatchBridge` are each small, single-purpose and stable (6–9 commits each).

**Strain.** One type: `ExerciseAnalyzer/VideoPoseSession.swift`, 730 → 1,813 lines in 18 hours, in 45 of 137
commits, 26 `@Published`, 46 private vars, 68 funcs, 98 `log.event` calls, nine jobs behind one `@MainActor`
class. The concrete symptoms:

1. The "what to do with a stored set" rule (stale version? models changed? re-detect in Auto?) is written four
   times with drift between them (`refreshStaleEntries` :218–234, `open(recent:)` :569–600, `rerunFromClip`
   :306–382, `analyzeExtracted` :815–829), and one path talks to another through an instance-variable side
   channel across an `await` (`rerunExercise` :81, :574, :775). `offline_pass` is emitted twice with different
   fields (:347–358 vs :766–774). `rerunFromClip` guards `analysisTask == nil` but not `refreshTask` (:307, :333):
   a start-panel "Instrumented run" during the launch refresh can interleave two re-runs.
2. Model readiness is polled in three `while predictor == nil` loops (:211, :267, :697) plus a fourth mechanism,
   `pendingLoadURL` (:125, :399, :469).
3. `RecentsStore.isStale` and `models(for:)` decode the whole `analysis.json` (every frame) to read one string
   (:197–211); the launch refresh does that twice per entry before decoding it a third time (:218, :225).
4. The frame-extraction loop exists twice (`OfflineAnalyzer.extract` :73–155 and `posetrack` main.swift
   :179–235); 3ba7902 changed both. The fixture JSON has four hand-written codecs (posetrack write :306–323,
   posetrack `--poses-from` :240–261, `PoseTrackFixtures.StoredTrack` :67–85, `pull-tracks.sh` :30–33) and
   `FrameRecord` is rebuilt field-by-field in six places; adding `bells`/`bell` touched 20 files (3b997e1).
5. The held-bell metric is computed three ways (`BellTracker.heldSummary` :119–144, posetrack :280–295,
   `TuningReports.bellHeldLine` :236–287); only the report has the loss classes and `inZone`, so the phone's
   `bell_held` and the lab's line can disagree.
6. Nothing in `ExerciseAnalyzer/` has a host test. The rerun/refresh/trim/undo/save/replace-in-Photos state
   machine is verified only by five simulator checks and the phone; #37, #42, #45, #46 all lived there.

**Recommendation.** No rewrite. Keep `ExerciseCore` and the views as they are; take the session apart along the
seams its own `// MARK:` comments already draw, and pull the three duplicated rules into single functions that
the host tests can see. Nine small steps, each one commit, each verified on the cheapest rung that sees it;
steps 1–4 and 6–7 are host-verifiable and low risk, step 5 (the split itself) is the one that needs a phone
session. Done in order, no step leaves the app in a state the current scripts cannot check.

**First three steps.**

1. `StoredSetPlan` (pure, in ExerciseCore): given the stored version and model set, the current ones, the mode
   and the stored exercise, return `.keep` / `.replay(exercise, reason)` / `.rerunFromClip(exercise, reason)`.
   Replace the four inline decisions; unit tests for each of today's cases including #42.
2. Version and model set into `RecentEntry` (index.json) with a one-time backfill; `isStale` and `models(for:)`
   stop decoding frames. `RecentsStore` becomes host-testable on a temp directory.
3. `OfflineJob`: one function for "models ready → extract → analyze → fill images → save → log" used by the user
   pass, the launch refresh and the instrumented run, with `where` and the exercise as parameters. One
   `offline_pass` field set; `rerunExercise` and the two task guards go away.

**Cost.** Steps 1–4: about a day of agent time, host tests plus one `just test-sim` each. Step 5 (the split into
`LoadedClip`, `CameraRecorder`, `ClipEditor`, `BugReporter`): a day, five commits, `test-sim` after each and one
gym session for camera, rotate, trim, save/replace. Steps 6–9 (one fixture codec, one held metric, shared
extraction loop, `trace` on all analyzers): half a day each, optional. Whole plan 2–3 days; stopping after
step 4 already removes the four-way rule, the polling and the launch-refresh cost, all without a phone.

---

## 1. What exists

### 1.1 Modules and responsibilities

| Unit | Lines | Does | Commits (week) |
|---|---|---|---|
| `ExerciseCore/Exercise.swift` | 212 | `ExerciseKind` registry, `ExerciseDefinition` (phases, gallery order, HUD metrics), `RepRecord`/`RepPosition`/`RepQuality`, `ExerciseAnalyzer` protocol, `PhaseStateMachine` | 3 |
| `BodySkeleton.swift` | 234 | pixel-space angles, per-frame side choice by confidence, get-up signals | 3 |
| four `*Analyzer.swift` | 287–458 | one state machine each over skeleton signals; own `Thresholds` struct; `trace` hook on Bulgarian and TGU only | 1–5 |
| `ExerciseDetector.swift` | 166 | which exercise, from floor time, arm cycles, knee asymmetry, foot elevation | 2 |
| `PoseTrack.swift` | 95 | `FrameRecord` (the one record: time, size, pose, box, analysis, bells, bell) and the ordered track with nearest/shift | 4 |
| `AnalysisPipeline.swift` | 129 | one analyzer over frames; `analyze(frames:)` (offline: static zones, backward fill), `restored`, `shifted`, crop, span | 6 |
| `Bell.swift`, `BellDetector.swift`, `BellColorSampler.swift`, `ModelPlan.swift` | 319/185/46/45 | tracker + colour (pure); Vision/CoreML detector, byte sampler, compute plan (behind `#if canImport`) | 9/6/2/1 |
| `FrameStatus.swift` | 133 | in-frame hint, `WatchStatus`/`WatchCommand` wire types | 6 |
| `posetrack/main.swift` | 328 | Mac tool: reader loop, own pose parse, detector, analysis, fixture write/merge | 6 |
| `ExerciseAnalyzer/VideoPoseSession.swift` | 1,813 | everything below in §1.2 | 45 |
| `OfflineAnalyzer.swift` | 171 | reader + both models per frame, heartbeat, cancel | 9 |
| `RecentsStore.swift` | 294 | index.json + folder per set (analysis.json, rep JPEGs, thumbnail, clip or Photos id, trim backup) | 9 |
| `CoreBridge.swift` | 75 | SDK `Keypoints` → `Pose`, `YOLOResult` → `FrameRecord`, `fillRepImages`, thumbnail | 2 |
| `CameraSource`, `FrameRecorder` (+`VideoFile`) | 101/286 | capture; H.264 writer, passthrough trim, stitch, Photos save/delete | 3/6 |
| `SessionLog`, `BugReport`, `CrashReports`, `RecordPrompt` | 80/77/101/71 | JSONL log; shake sheet; MetricKit + signal handler; watch-wake notification | 2–4 |
| `ContentView.swift` | 823 | main screen, HUD, controls, start panel, plus `MeViewZoom`, `VideoLayerHostView`, `PlayerView`, `CameraPreviewView`, `PickedMovie` | 29 |
| `WorkoutGalleryView`, `RepGalleryView`, `KeyframeViewer`, `PoseOverlayView`, `WatchModeView`, `EdgeStepper`, `PhotosSuggestions` | 63–386 | views, mostly value-driven | 1–6 |
| `ExerciseAnalyzerWatch/` | 274 | `PhoneLink` (WCSession, forwards its log), `WatchContentView` | 6–11 |
| tests | 921 | see §1.6 | |

### 1.2 What `VideoPoseSession` holds (by its own MARKs and line ranges)

| Lines | Job |
|---|---|
| 139–200 | init: wiring of watch/crash/notifications/timers/player observers; kicks `refreshStaleEntries`, `SWING_DEBUG_RUN` |
| 207–257 | launch refresh of stale sets (replay or re-run) + gallery thumbnail choice |
| 263–298 | instrumented run over every set |
| 306–382 | `rerunFromClip`: the models again over a stored set (used by refresh and the run) |
| 384–459 | model loading, compute-plan logging, detector switch |
| 464–518 | file / Photos import |
| 521–631 | open a stored set (iCloud fetch, replay vs re-run vs re-detect), status line, bell weight |
| 634–657 | write the current clip + analysis into Recents |
| 659–838 | the user-facing offline pass: cancel, `analyzeAndPlay`, `finishAnalysis`, `analyzeExtracted`, empty-recording prompt |
| 841–864 | exercise mode |
| 866–957 | player item install, video-track/player-layer logging, `adopt(pipeline:)` |
| 959–1076 | play/pause/seek/step/rep/phase/checkpoint navigation, display link replay |
| 1080–1182 | live ingest: sample buffer → SDK predict → live detector lock → pipeline → HUD/log/watch/preview |
| 1188–1245 | watch: keep-awake, status push, command dispatch |
| 1248–1270 | live crop easing, `show(frame)` |
| 1274–1523 | camera lifecycle: start, attach, rotate/segment, level cycle, flip, cancel, stop, finish (stitch → trim → analyze) |
| 1525–1691 | trim to reps, undo (with Photos restore), save (with Photos replace) |
| 1693–1792 | bug screenshot/frame capture, images, context, `bugs.jsonl` |

Growth: 730 lines at the repo move (09-12 10:22), 1,000 by 16:10, 1,500 by 18:29, 1,628 at 21:54, then one
commit (8fde7b7, 04:52) added 199 for the launch re-run and the instrumented run.

### 1.3 Data flow: frame → stored set

**Live** (`source == .camera`): `CameraSource.onFrame` (capture queue) → `FrameRecorder.append` (its queue) and
`Task { @MainActor cameraFrame }` → `ingest` (:1080): one frame in flight, `predictor.predict` on
`inferenceQueue` → `on(result:)` hops back to the main actor → `handle(result:)` (:1115): live detector until
locked (60 frames and ≥70 %, or 120 frames), `pipeline.process(result:)` (CoreBridge) → `FrameRecord` appended
to the live `PoseTrack`, HUD, `log.frame`, `FrameStatus` → watch push, 1 fps preview JPEG. **No bell detector,
no static zones, no backward fill on the live path** (by design: detector is offline-only). Done →
`finishCamera` (:1472): stop, stitch rotated segments, `trim(using: livePipeline, thenAnalyze: true)` → the
recording's rep span is cut passthrough → `analyzeAndPlay(trimmed)` → the offline path. The live track is
discarded; the offline pass is the truth.

**Offline** (import, open, re-run): `analyzeAndPlay` (:691) → wait for model (poll) → `installPlayerItem` with an
empty pipeline → `waitForPlans` → `OfflineAnalyzer.extract` (:60): detached task, `AVAssetReader` +
`AVAssetReaderVideoCompositionOutput` (rotation applied, BGRA), per frame inside an `autoreleasepool`: detector on
a global queue in parallel with `predictor.predict` on the reader thread, `FrameRecord(result:)` rebuilt with
`bells`; heartbeat every 60 frames; cancel forwarded. Returns `[FrameRecord]` (no analysis) + `Summary` →
`finishAnalysis` (:763) → `analyzeExtracted` (:815): mode/detector chooses the exercise →
`AnalysisPipeline.analyze(frames:exercise:)` (static zones → tracker per frame → backward fill) →
`fillRepImages` (AVAssetImageGenerator at each peak) → `adopt(pipeline:)` publishes reps/crop/frame → every frame
and rep logged → `rememberCurrent` → `RecentsStore.save`: analysis.json (`AnalysisSnapshot` v2: version, models,
exercise, frames, reps), rep JPEGs, thumbnail, clip copy when not in Photos, index.json.

**Re-analysis without the model** (mode change, stale version, Auto re-detect): `extractedFrames` (the last
pass's frames, held in the session) → `analyzeExtracted` again. **Re-run with the model** (models changed):
`rerunFromClip` (background, refresh or instrumented) or `open(recent:)` → `analyzeAndPlay` with `rerunExercise`
set so the fixed mode does not re-read the set.

**Playback**: no frames are pulled from the player; `CADisplayLink` reads `player.currentTime()` and shows
`track.nearest(...)` (:1064). Seeks re-publish the player's landed time.

### 1.4 Where state lives

- `VideoPoseSession` (main actor): 26 published (source, activity, reps, latestFrame, times, camera, watch
  mode, frame status, crop, mode, exercise, detection, rate, instrumented run, cancel flag, undo flag, prompt,
  can-save) and 46 private (predictor, detector, pipeline, `extractedFrames`, live detector state, inference
  gate, camera/recorder/segments, the loaded-clip tuple `currentFileURL / trimmedURL / currentOrigin /
  currentEntryID / currentRecordedAt`, `untrimmed`, `replacedOriginalID`, `rerunExercise`, `analysisTask`,
  `refreshTask`, `planTasks`, bug images, watch timers). The loaded-clip tuple is written as a block in five places
  (:473–478, :553–558, :801–804, :1516–1520, :1581–1584).
- `RecentsStore` (main actor): `entries` in memory + index.json; everything else on disk per set.
- `AnalysisPipeline`: analyzer state, `PoseTrack`, `reps`, `bellTracker` (with `staticZones`).
- `UserDefaults`: `exerciseMode`, `bellDetector`, `overlayMode`, `meView`, `galleryHeight`, `hideAnalyzedClips`.
- `WatchBridge` / `PhoneLink`: last sent status, reachability, preview.
- Off the main actor: only the two model loops (`inferenceQueue`; the detached reader) and the log's write queue.
  `refreshStaleEntries` runs `AnalysisPipeline.analyze`, JSON-encodes every frame of every stale set and writes
  JPEGs on the main actor at launch (:235–247); story 015 records 22 entries refreshed in one launch.

### 1.5 How the views reach the session

`ContentView` owns `@StateObject session`; `BugReportSheet`, `KeyframeViewer`, `WatchModeView` and
`WorkoutGalleryView` (only for the shake sheet) take `@ObservedObject var session`. `RepGalleryWidget/Sheet`,
`PoseOverlayView`, `PhotosSuggestionsRow`, `EdgeStepper` take values and closures. Everything the views need is a
published property or a method on the one object, so the session is the app's whole view model; `currentTime`
publishes 30×/s and `ContentView.body` re-evaluates with it (the `.onChange(of: session.currentTime)` at :140
throttles only the `clock` log line, not the render). Fine today; it is why the session cannot shrink by moving
things into the views.

### 1.6 Log, bug reports, stories

- `SessionLog.event(type, fields)` → JSONL; 116 call sites in the app (98 in the session), string-typed names,
  ad-hoc field sets; `WatchBridge`, `PhotosSuggestions`, `WorkoutGalleryView`, `CrashReports` use an `onEvent`
  hook into the same log. The event catalogue in DEBUGGING.md is kept by hand.
- Rung 2 reads the log, not the screen: `sim-smoke.sh` waits on `analyzed`/`trim`/`analysis_cancelled` and
  greps fields; `sim-debug-run.sh` on `recents_saved`/`debug_run`/`bell_held`. So event names and fields are a
  contract between the app and the scripts, with nothing enforcing it.
- Shake → `captureBugScreenshot` → `reportBug` → `bug_report` event + `Documents/bugs.jsonl` + images;
  `bugs-monitor.sh` polls `bugs-check.sh`; `file-bugs.sh` files once per `reported_at` marker and gists the images.
- Stories: 37 stories in six journey files, every one with a `Status:` naming commits and the rung; bugs get an
  `Issues:` line. Analysis notes: one file per exercise plus the detector, Experiments entries with the table
  that decided each rule (kettlebell-detector.md is 336 lines of exactly that).

### 1.7 What the tests cover

Host (`ExerciseCoreTests`, ~1 s): detection per fixture (≥75 %) and under mirroring; rep count per fixture,
every phase position present, score in range; swing counts and lockout under mirroring; rep span and stable
crop; skeleton angles on synthetic poses; track nearest/shift; frame status and watch message round trip; bell
tracker (13 tests: start/follow/coast/rest/zones/colour/flat/head/nearest-wrist/backward fill), colours, dense
tensor parse in Float16/32; get-up stages; every archived phone track analyzes. Reports (print, no assert):
per-fixture traces, threshold sweeps, signals, the held-bell line with loss classes.

Rung 1.5: `posetrack` on a clip; model trials in Python. Rung 2: five checks (three counts, one trim, one
cancel) plus the debug-run script. Rung 3: the phone.

Not covered below the phone: everything in `ExerciseAnalyzer/` (no test target), in particular the stored-set
decision, `RecentsStore` save/load/stale/models, trim/undo/save/replace, the camera flow, the watch glue.

## 2. What to keep, and why

- **`ExerciseCore` as the platform-free package with `FrameRecord` as the boundary.** Every analyzer, detector
  and tracker change this week was decided by numbers from fixtures in seconds (the eight-row table in
  kettlebell-detector.md; #4, #14, #15, #16 fixtures). This is the design paying for itself; nothing below
  proposes moving that boundary.
- **`AnalysisPipeline.analyze(frames:)` as the one offline analysis entry.** App, Mac tool and tests all call it
  (VideoPoseSession :235/:359/:830, posetrack :269, tests throughout). Re-analysis never touches the model.
- **`ExerciseKind` → `ExerciseDefinition` + analyzer, phases as strings with aliases.** The get-up stages
  (1f815f5) changed Exercise.swift by 12 lines and the UI by 4.
- **`BellTracker` pure with `Thresholds`, and bells stored in fixtures.** The whole detector lab ran on rung 1;
  Codex's two hypotheses shipped with `BellTests`.
- **`OfflineAnalyzer.extract` as a static function with progress/heartbeat closures and forwarded cancel.**
  Small, correct after #37/#43/#46, and independent of the session. Keep its shape; §3 reuses it as is.
- **`RecentsStore`'s on-disk layout** (folder per id, `analysis.json`, `rep-N-phase.jpg`, `thumbnail.jpg`,
  index.json). `pull-tracks.sh` and the fixture flow depend on it. Keep the files; change what the index carries.
- **`SessionLog` JSONL, the event-driven simulator checks, the bug marker flow, stories with `Status:`,
  analysis notes with Experiments.** These are the repo's memory and its cheapest test rungs.
- **`CameraSource`, `FrameRecorder`, `VideoFile`, `WatchBridge`, `PhoneLink`, `CrashReports`.** Each does one
  thing behind a small surface and has not needed to change with the analysis work.
- **The views.** Value-driven where they can be; the HDR rules (no transform on the player layer, zoom by frame)
  are encoded in `VideoLayerHostView` and `MeViewZoom` and should stay exactly there.

## 3. Strains, with evidence

### 3.1 One type carries nine jobs

`VideoPoseSession.swift`: 1,813 lines, 45/137 commits, +1,083 lines in 18 hours, the last commit +199. It is the
model loader, the launch refresher, the lab runner, the importer, the Recents reader and writer, the offline
orchestrator, the player, the live analyzer, the watch glue, the camera controller, the clip editor and the bug
reporter (§1.2). Every feature this week landed here first: the watch (6 commits), zoom (2), rotation (1), trim
and undo (4), cancel (2), empty recording (1), screenshots (1), the detector (5), the re-run (2). The
instrumented run is a lab feature and lives between the model loader and the file importer.

### 3.2 The stored-set rule, four times

| Site | Rule as written |
|---|---|
| `refreshStaleEntries` :218–234 | stale **or** current models ⊄ stored → if models differ and clip reachable, re-run; else replay stored frames, re-detect in Auto at ≥70 |
| `open(recent:)` :569–600 | models ⊄ stored → `rerunExercise = stored`, `analyzeAndPlay`; else if stale → replay "analyzer_version"; else Auto re-detect ≥70 → replay "recents_redetect" |
| `rerunFromClip` :306–382 | extract, analyze as `stored.exercise`, `bell_held`, save with `loadedModels`; its own `offline_pass` fields |
| `analyzeExtracted` :815–829 | mode fixed → `stored ?? kind`; Auto → detect (no threshold) |

Same question, three thresholds' worth of drift (Auto re-detect needs ≥70 in two places and nothing in the
third), two `offline_pass` shapes, two `recents_refreshed` shapes, two thumbnail choosers (`galleryThumbnail`
:253 and `rememberCurrent` :643–646), `storedModels(_:)` :92 duplicated inline at :569. #42 was exactly this
class of bug (a fixed mode re-reading a stored get-up). `rerunExercise` is set in one method and consumed in
another after an `await` (:81, :574, :775–777); nothing ties them together but the comment.

### 3.3 Waiting for the model, four ways

`while predictor == nil { sleep 100 ms }` at :211, :267, :697; `pendingLoadURL` at :125/:399/:469;
`planTasks`/`waitForPlans` at :415–431 for the compute plans. The models are a resource with a readiness; the
session polls it.

### 3.4 Two tasks, priority by guard

`analysisTask` (user pass) and `refreshTask` (background re-run). `analyzeAndPlay` cancels `refreshTask` (:693);
`rerunFromClip` refuses while `analysisTask != nil` (:307) but not while another `refreshTask` is running and
overwrites it (:333); `startInstrumentedRun` checks `instrumentedRun == nil, analysisTask == nil` (:264) but not
`refreshTask`. Init awaits the refresh before the `SWING_DEBUG_RUN` hook (:195–198), so the simulator run is
serialized; the start-panel button (ContentView :441–444) is not. I did not run it; read as a probable
interleaving, not a confirmed bug.

### 3.5 Recents reads the whole track to answer a yes/no

`RecentsStore.models(for:)` :197–203 and `isStale` :205–211 decode `AnalysisSnapshot` (all frames, all reps)
for one string each. `refreshStaleEntries` calls both per entry (:218) and `loadPipeline` again for the stale
ones (:225). For a 4,000-frame get-up that is three full decodes of a multi-MB JSON on the main actor at launch,
per set. The version and the model set are entry metadata and belong in `index.json`.

### 3.6 Duplicated paths

- **Extraction loop**: `OfflineAnalyzer.extract` :73–155 and `posetrack` :179–235 both build the reader, the
  composition, the BGRA output, the parallel detector on a global queue with a `DispatchGroup`, and the
  `FrameRecord`. 3ba7902 changed both (+17, +14). The pose parse differs by necessity (SDK `BasePredictor` in
  the app, Vision + `parse()` :120–150 on the Mac), and the doc's "poses match to 3 px mean" is the only guard
  that they stay equivalent.
- **Fixture codec** ×4 plus `AnalysisSnapshot` as a fifth shape of the same data; `version: 1` written and never
  checked. `FrameRecord` rebuilt field-by-field at OfflineAnalyzer :129, PoseTrack :79–82, Bell :110–111,
  posetrack :229/:256, fixtures :56–63. `bells`/`bell` touched all of them (3b997e1: 20 files).
- **Held-bell metric** ×3 (§ summary 5). `BellTracker.heldSummary` was added in 8fde7b7 to give the phone the
  lab's numbers; it does not compute `inZone` or the loss classes, so `bell_held` on the phone is a coarser
  number than the report's and the doc has to say which one it is quoting.

### 3.7 Tests cannot reach the app layer

No test target for `ExerciseAnalyzer/`. The decisions in §3.2, the `LoadedClip` tuple transitions, trim/undo
bookkeeping, `RecentsStore.save`'s same-clip replacement (story 013), the models-subset rule: all verified by
`sim-smoke.sh` (5–8 min) or by hand. Most of this is Foundation-only and could run in a second. The `trace`
hook exists on two of four analyzers (Bulgarian :66, TGU :134), so swing and pistol tuning reports read
positions instead of transitions.

### 3.8 Smaller

- Event names and fields are strings in 116 places; the scripts grep them. A typo is a silent test hole.
- `ContentView.swift` (823 lines, 29 commits) carries the layer hosts and the zoom math beside the screen.
- `WorkoutGalleryView` takes the session only to present the shake sheet (:17–18, :95–97).

## 4. Target architecture

Same modules, same data flow, same ladder. What changes: the session becomes a thin coordinator of four
collaborators, the three duplicated rules become one function each, and the app layer gets a host test target.

```
ExerciseCore (unchanged surface, plus:)
  StoredSetPlan          pure: (stored version, stored models, current, mode, exercise) → keep / replay / rerun
  TrackFile              the one fixture codec (versioned), used by posetrack, tests, pull-tracks
  BellTracker.heldSummary grows the loss classes + inZone; report and posetrack print it
  ExerciseAnalyzer.trace  on the protocol, default nil
  [later] FrameExtractor  #if canImport(AVFoundation): reader loop + parallel detector, pose source injected

ExerciseAnalyzer
  ModelSet               predictor + detector + plans; `await ready()`; `names` (the model-set string)
  OfflineJob             ready → extract → analyze(plan) → fill images → save → log; params: url, exercise, where, sinks
  LoadedClip             struct: url, trimmedURL, origin, entryID, recordedAt, untrimmed, replacedOriginalID
  CameraRecorder         start/attach/rotate/flip/cancel/finish(+stitch) → URL
  ClipEditor             trim / undo / save / replace-in-Photos over a LoadedClip + RecentsStore
  BugReporter            screenshot, frame, context, bugs.jsonl
  VideoPoseSession       player, playback, pipeline adoption, published state, watch glue; owns the five above
  RecentsStore           index carries analysisVersion + models; frames decoded only by loadPipeline
  ExerciseAnalyzerTests  host target: StoredSetPlan cases, RecentsStore on a temp dir, LoadedClip transitions
```

The views keep talking to `VideoPoseSession` (it forwards to the collaborators), so no UI commit is needed.

**How the app, the Mac tool and the tests share the pipeline after this**: all three go
`[FrameRecord] → AnalysisPipeline.analyze` as now; the tool and the tests also share `TrackFile`; the app and
the tool share the extraction loop once step 8 lands, with only the pose source differing (SDK vs Vision).

**How a change is verified after this** (same ladder, one new row):

| Change | Rung |
|---|---|
| analyzer, detector, skeleton, tracker | host, as today |
| stored-set decision, Recents metadata, trim bookkeeping | host (`ExerciseAnalyzerTests`), new |
| offline job (extract → save) | `sim-smoke.sh` `check` + `check_cancel`, `sim-debug-run.sh` |
| camera, rotate, trim on HDR, Photos replace, watch | phone, as today |

### 4.1 The sequence

Each step is one commit, leaves every current script passing, and names its rung.

| # | Step | Buys | Risks | Touches | Verify |
|---|---|---|---|---|---|
| 1 | `StoredSetPlan` in ExerciseCore; the four sites call it | one rule, #42-class bugs get a test, the reasons (`load`/`analyzer_version`/`recents_redetect`/`rerun_models`) come from one enum | the four variants differ today; write a test per current behaviour first, then unify (decide the Auto threshold once) | Exercise.swift or a new file (~60 lines), VideoPoseSession −~40 | host |
| 2 | `RecentEntry.analysisVersion` + `models` in index.json, backfilled once from analysis.json on first read; `isStale`/`models(for:)` read the entry | launch refresh stops decoding tracks; `RecentsStore` testable on a temp directory | migration: old index entries lack the fields; backfill reads each once and rewrites the index | RecentsStore (~30), VideoPoseSession (~5) | host + `test-sim` (`SWING_OPEN_RECENT`) |
| 3 | `OfflineJob`: the body of `rerunFromClip` and `analyzeAndPlay`/`finishAnalysis` as one async function with `where`, exercise, progress and status sinks; one `offline_pass`, one `recents_refreshed`, one thumbnail chooser; `rerunExercise` deleted | the three passes are one; the next lab feature is a parameter, not 199 lines | the user pass installs the player item and toggles `activity`/`canCancelAnalysis`; keep those as closures the session passes in; task ownership (`analysisTask` vs `refreshTask`) becomes one `currentJob` with a priority flag | VideoPoseSession −~250, new OfflineJob ~200 | `test-sim` all five + `sim-debug-run.sh` |
| 4 | `ModelSet`: load both models and plans, `await ready()` (continuation over `BasePredictor.create`), `names` | three polling loops and `pendingLoadURL` go; the model-set string is defined once | `load(url:)` before ready must still queue: `await models.ready()` inside the job does it | VideoPoseSession −~60 | `test-sim` (`check`, opens before the model loads) |
| 5a | `LoadedClip` struct replacing the six fields | the five block-writes become one assignment; transitions testable | none beyond mechanical | VideoPoseSession | host test of transitions + `test-sim` trim |
| 5b | `CameraRecorder` (:1274–1523) | 250 lines out; the rotate/segment logic isolated | phone-only verification; keep the log events byte-identical | VideoPoseSession → new file | phone: record, rotate, flip, Done |
| 5c | `ClipEditor` (:1525–1691) over `LoadedClip` + `RecentsStore` | trim/undo/replace bookkeeping in one place with a host test for the undo/replace state | Photos replace needs the phone | new file | `test-sim` trim + undo; phone: save after trim, undo |
| 5d | `BugReporter` (:1693–1792) | 100 lines out; the sheet takes the reporter | none | new file, BugReport.swift | `test-sim` with `SWING_BUG` |
| 6 | `TrackFile` codec in ExerciseCore; posetrack, `PoseTrackFixtures`, `--poses-from` and a `--from-snapshot` (analysis.json) mode use it; `pull-tracks.sh` calls posetrack for the conversion; decoder checks `version` | one place to add a field; a round-trip test | must decode the 22 existing files byte-for-byte as today; add a test that decodes every fixture and compares frame counts/first frame to the current decoder before deleting it | ExerciseCore, posetrack, tests, script | host |
| 7 | `heldSummary` grows loss classes + `inZone`; `bellHeldLine` and posetrack print it | report, tool and phone print one number | none | Bell.swift, TuningReports, posetrack | host (`TuningReports` output identical) |
| 8 | `FrameExtractor` in ExerciseCore (`#if canImport(AVFoundation)`): reader + composition + parallel detector + heartbeat + cancel, with a `(CMSampleBuffer) -> (pose, box)?` source; `OfflineAnalyzer.extract` and posetrack call it | one loop; a change like 3ba7902 is one file | the SDK source needs the sample buffer, Vision the pixel buffer: pass the sample buffer, derive the pixel buffer inside; Mac `parse()` stays Mac-only | OfflineAnalyzer shrinks to the SDK source, posetrack shrinks by ~60 | `test-sim` `check` ×3 + `just analyze` fixture diff |
| 9 | `trace` on the `ExerciseAnalyzer` protocol; swing and pistol emit transitions | tuning reports read transitions for all four | none | four analyzers | host |

Order matters only in that 3 wants 1 and 4 wants nothing; 5a before 5b–5d; 6 before 8. Stopping after 4 is a
sound place to stop; stopping after 7 leaves only the split's second half and the shared loop.

### 4.2 What stays untouched

`ExerciseCore` analyzers, `BodySkeleton`, `ExerciseDetector`, `BellTracker`/`BellDetector`/`BellColorSampler`,
`PoseTrack` and the `FrameRecord` shape, `AnalysisPipeline`, `FrameStatus`; the on-disk Recents layout and
`analysis.json`; `SessionLog` and every event name and field (the scripts depend on them); all views and the
HDR rules; the watch app; `CameraSource`, `FrameRecorder`, `VideoFile` internals; the scripts, the justfile,
the docs structure and the test ladder.

### 4.3 What it would cost

- Steps 1–4: one day of agent time; each a host test and one `just test-sim`. No phone.
- Step 5: one day, four commits; `test-sim` after each; one gym session at the end for camera, rotate, trim on
  an HDR clip, save-after-trim and undo, watch commands.
- Steps 6–7: half a day, host only. Step 8: half a day plus three simulator counts and a fixture diff. Step 9:
  an hour.
- Total 2–3 days. The risk concentrates in 5b/5c (phone-only flows) and 6 (fixture bytes); both have a
  before/after check named above. Everything else is behind existing tests or simulator checks.

### 4.4 Open questions for you

1. Does the Ultralytics iOS package build for macOS? If it does, step 8 can use the SDK's predictor on the Mac
   too and `posetrack`'s own `parse()` goes away with the "3 px mean" caveat. I did not check the dependency.
2. The Auto re-detect threshold: 70 in the refresh and on open, none in `analyzeExtracted`. Step 1 needs one
   answer.
3. Should the instrumented run stay in the app once `OfflineJob` exists, or become `posetrack --all-sets` over
   `just pull-tracks`? It only measures the phone's models, so probably stay; but it need not be a start-panel
   row forever.
4. `refreshStaleEntries` on the main actor at launch (§1.4): if the gallery ever hitches on a launch with many
   stale sets, step 3's job is the place to move the analyze/encode off the main actor. I have no measurement
   that it hitches today.
