# Exercise Analyzer: architecture decision brief

2026-09-13. Prepared for Igor; recommendation only. Review of `codex-bell` at `6e2b69d45b4b3b11f3f2dbacde68fba63ddcd682`, including the two pre-existing research edits described below.

## Summary page

**Recommendation:** keep the existing architecture's core and refactor the boundaries around it. The useful destination is three layers: **ExerciseCore** for observations and analysis, **ExerciseMedia** for the shared Apple video/model pipeline, and the **app** for session coordination, playback, recording, Photos and presentation. Add one Swift package library target, not a framework of services. The watch stays a remote control.

**Keep:** the four exercise analyzers and their small protocol; the stored-pose replay pipeline; exercise-defined HUD/gallery metadata; Photos identifiers and local JSON storage; separate playback and inference; the host → Mac model → simulator → phone test ladder; analysis experiments and stories as the spec. These already make useful changes cheap and preserve the gym-first UI.

**Strain:** `VideoPoseSession` is now 1,628 lines, but its size is a symptom. It owns several asynchronous operations that read and write the same current-set fields. Open and launch refresh implement overlapping policies with different outcomes. Raw sightings and derived tracker output share `FrameRecord`, so replay can retain old bell decisions. The app and Mac tool share the analyzer and bell detector, but maintain separate pose extraction loops and different diagnostics. Storage provenance describes loaded model names rather than exactly what produced the observations.

**First three steps:**

1. Separate raw observations from derived analysis at the replay boundary; share a compact track codec. Prove that replaying stored observations runs today's tracker and that exporting a phone track preserves bell sightings.
2. Extract one tested stored-set refresh policy. Preserve set identity and extraction provenance; make restore, pose replay and video extraction explicit decisions used by both open and launch refresh.
3. Give each foreground operation an immutable request and an ID. One owner handles cancellation, model readiness and publication; late results cannot update another set. Keep `VideoPoseSession` as the view-facing facade during this work.

**Cost:** estimate **4–6 engineer-days for those three steps**, **10–16 for the full staged plan**, plus access to the phone/watch for roughly 2–3 focused verification sessions. These are planning estimates, not measured delivery times. The biggest risks are stored-data compatibility, SDK/CLI pose parity, cancellation ordering and recording lifetimes. Each step has a stopping point; no rewrite or immediate UI redesign is justified. There is no promised inference-speed gain: the detector remains off by default.

**Decision I recommend:** fund the first three steps, then reassess whether sharing the media pipeline is worth the remaining cost. This review changed no repository files, ran no builds or tests, and made no commits. Its findings are static evidence; historical performance and verification numbers are attributed to the repository's notes and commits.

---

## Scope and evidence

Read `AGENTS.md`, all four required documents, all six story journeys, all exercise/detector analysis notes, the application and watch Swift sources (including the complication), the package sources and tests, the model-trial scripts, and the build/bug/fixture tooling. Read the local git log for September 6–13 and selected diffs around the detector, re-runs, cancellation and instrumented runs. Relevant history in this checkout is concentrated on September 11–12. No remote branch or issue status was fetched.

Repository references below are relative to `/Users/idvorkin/gits/exercise-analyzer/.claude/worktrees/codex-bell`; `path:line` identifies the inspected code. Names under “target” are proposals, not existing types.

Two edits existed before the review: `ExerciseCore/Tests/ExerciseCoreTests/TuningReports.swift` (+208/−4 lines) and `docs/analysis/kettlebell-detector.md` (+29). They contain second-opinion research, not production tracker changes. Report citations use their working-tree line numbers. Their experimental results are not represented here as committed behavior or new verification performed by this review.

## What exists, module by module

### Package and analysis domain

`ExerciseCore/Package.swift:4` declares one library, one `posetrack` executable, and one XCTest target with copied fixtures. The app depends on this library and UltralyticsYOLO; the watch depends on the library (`ExerciseAnalyzer.xcodeproj/project.pbxproj:150`, `:176`). There is no app unit-test target in the project inspected.

| Types / files | Responsibility and owned state |
|---|---|
| `Pose`, `PosePoint` (`Pose.swift:10`) | App-owned Codable keypoints, normalized and pixel coordinates, confidence. Avoids storing SDK types. |
| `CocoKeypoint`, `BodySide`, `BodySkeleton` (`BodySkeleton.swift:12`) | Joint layout, coherent side selection, missing-joint checks, pixel-space angles and get-up signals. A skeleton is a per-pose value. |
| `ExerciseKind`, `ExerciseMode`, `ExerciseDefinition`, `PhaseInfo`, `MetricInfo` (`Exercise.swift:10`) | Four known exercises, Auto/fixed preference, analyzer construction, phase aliases, HUD and gallery definitions. |
| `ExerciseAnalyzer`, `PhaseStateMachine` (`Exercise.swift:169`) | Small per-pose interface and common phase/rep bookkeeping. Each analyzer owns its own machine, thresholds and histories. |
| `ExerciseFrameResult`, `RepRecord`, `RepPosition`, `RepQuality` (`Exercise.swift:100`) | Per-frame metrics and completion, phase checkpoints and scores. `RepPosition.image` is an in-memory `CGImage`, excluded from Codable. |
| `KettlebellSwingAnalyzer` (`KettlebellSwingAnalyzer.swift:42`) | Top/connect/bottom/release, wrist-height smoothing and peaks, duration rejection, rep metrics and feedback. |
| `PistolSquatAnalyzer`, `SingleLegTracker`, `SingleLegFrame` (`PistolSquatAnalyzer.swift:22`) | Leg voting, knee/head signals, descent/ascent checkpoint search and quality. `SingleLegTracker` is also used by the Bulgarian analyzer. |
| `BulgarianSplitSquatAnalyzer` (`BulgarianSplitSquatAnalyzer.swift:30`) | Front-foot voting, elevation history, learned standing height, head-travel phases, knee/lean scoring and string trace hook. |
| `TurkishGetUpAnalyzer` (`TurkishGetUpAnalyzer.swift:50`) | Coarse count machine plus ordered stages, filtered uprightness, held conditions, overhead-side votes, missing-stage filling and quality. The stage logic is deliberately subordinate to counting. |
| `ExerciseDetector`, `ExerciseDetection` (`ExerciseDetector.swift:10`) | Accumulates movement statistics, then classifies with confidence and reasons. Whole-track helper and incremental live use share the same detector. |
| `FrameRecord`, `PoseTrack` (`PoseTrack.swift:9`) | Stores observations AND derived frame results/bell choices. Time ordering, binary nearest lookup and trim-time shifts. |
| `AnalysisPipeline`, `PersonCrop` (`AnalysisPipeline.swift:11`) | Owns analyzer, tracker, growing track and reps; replay, restore, trim-copy, robust crop and rep span. Whole-track analysis adds static-zone learning and backward bell fill. |
| `BellSighting`, `BellTracker`, `BellColor` (`Bell.swift:12`) | Raw box/confidence/color, stateful hand association/coasting/rest/color gates, whole-track zones/backward fill, and color-to-weight mapping. |
| `FrameStatus`, `WatchStatus`, `WatchCommand` (`FrameStatus.swift:10`) | Framing hint and small Codable phone/watch contract with backward-compatible defaults. |
| `AnalysisVersion` (`AnalysisVersion.swift:8`) | One manually bumped derivation version, currently `2026-09-12.10`. |

The package is host-testable, but “platform-free” is no longer literal. It imports CoreGraphics, includes optional `CGImage`s, and now houses Vision/Core ML `BellDetector`, CoreVideo `BellColorSampler`, and `ModelPlan`. `BellDetector.swift:11` uses conditional compilation; `BellColorSampler.swift:9` directly imports CoreVideo. Removing all Apple geometry types would buy little for this app. Separating model execution from analysis would buy a clear dependency boundary.

### App and platform components

| Types / files | Responsibility and state |
|---|---|
| `ExerciseAnalyzerApp` (`ExerciseAnalyzerApp.swift:11`) | Ambient/mixing audio setup, notification routing and crash registration. |
| `VideoPoseSession` (`VideoPoseSession.swift:23`) | Main-actor observable facade; model loading/plans, live inference, camera/recorder lifecycle, exercise choice, offline jobs, stored-set refresh, Recents save, playback clock/navigation, trim/undo/Photos, watch presentation/status and bug capture. |
| `OfflineAnalyzer`, `ResultCatcher`, `Summary`, `Heartbeat` (`OfflineAnalyzer.swift:13`) | Oriented AVAssetReader pass on a detached worker, synchronous SDK pose prediction and optional bell prediction, progress/timing/memory reports, explicit cancellation forwarding. |
| `CoreBridge` extensions, `FrameImage` (`CoreBridge.swift:13`) | SDK-to-domain conversion, most-confident-person selection, live pipeline adapter, asynchronous rep-still filling, pixel-buffer thumbnails. |
| `CameraSource` (`CameraSource.swift:9`) | Capture device/session, camera output queue, orientation/mirroring, zoom and preview layer. |
| `FrameRecorder` (`FrameRecorder.swift:9`) | Serial writer queue, fragmented H.264 recording, first timestamp, partial-file recovery and completion. |
| `VideoFile` (`FrameRecorder.swift:99`) | Keyframe/decode-time-aware trim, HEVC fallback, orientation-segment stitching, Photos save/delete. Several platform operations share a file, but the recorder itself is already distinct. |
| `RecentEntry`, `AnalysisSnapshot`, `RecentsStore` (`RecentsStore.swift:13`) | Published index plus synchronous JSON/image/file persistence, deduplication, Photos references/fetch, backups, schema/model/analyzer stamps and reconstructed pipelines. |
| `PhotosSuggestions` (`PhotosSuggestions.swift:11`) | Read permission, bounded recent-clip query, analyzed marking and thumbnail cache. |
| `SessionLog` (`SessionLog.swift:10`) | Serial JSONL writer; numeric frame/rep events and nonfinite-value handling. |
| `CrashReports` (`CrashReports.swift:41`) | MetricKit subscription and crash files, plus a separate signal fallback. |
| `WatchBridge` (`WatchBridge.swift:10`) | WatchConnectivity transport, changed-status throttling, application context, commands, previews and forwarded watch logs. |
| `RecordPrompt`, `NotificationRouter` (`RecordPrompt.swift:10`) | Permission preparation and notification-mediated recording when the phone is backgrounded. |
| `ShakeDetector`, `BugReportSheet` (`BugReport.swift:12`) | Shake detection and note-entry UI. Evidence capture and report writing still live in the session. |

### Presentation and watch

`ContentView.swift:15` constructs the session with `@StateObject`. It owns sheets, picker selection, scrub-in-progress values, gallery focus and persisted view preferences. It reads the session's published state and invokes methods directly. This is a reasonable SwiftUI entry point; no global store is needed.

`KeyframeViewer` and `WatchModeView` observe the whole session. `WorkoutGalleryView` observes `RecentsStore` and usually receives action/log closures, but additionally receives the entire session for its bug sheet (`WorkoutGalleryView.swift:10`). `RepGalleryWidget`/`RepGallerySheet`/`RepRow` take values and closures; `GalleryLayout` shares their column sizing. This is the preferable existing pattern for leaf views.

`ZoomTransform`, `MeViewZoom`, `VideoLayerHostView`, `PlayerView` and `CameraPreviewView` live in `ContentView.swift:614`. They apply video zoom by layer-frame resizing. `PoseDrawing`, `PoseOverlayView`, and `PoseThumbnail` share skeleton drawing; the overlay also draws the tracked bell. `EdgeStepper` owns touch/hold presentation. `WorkoutDay` and `ExerciseSets` compute day/exercise groupings inside `WorkoutGalleryView.swift:157`; its remaining views render headers and cards. `PickedMovie` is the Photos transferable file adapter.

On the watch, `ExerciseAnalyzerWatchApp` owns `PhoneLink`. That main-actor object decodes status, tracks reachability/receipt time, sends commands and triggers haptics; `WatchContentView` owns a two-second UI clock and presents recording/idle/stale/backgrounded states. `LaunchProvider`, `LaunchEntry`, `LaunchComplicationView`, `LaunchComplication` and `ComplicationBundle` form a static launch widget. No analysis runs on the wrist. Keep the explicit decision against a workout session recorded in story 018.

## Frame-to-stored-set data flow

### Live recording

1. `startCamera` resets live analysis and asks for access (`VideoPoseSession.swift:1089`). `CameraSource` delivers oriented, mirrored BGRA sample buffers on its capture queue.
2. Every delivered sample is offered to `FrameRecorder.append`; separately its pixel buffer/time is sent to the main actor (`VideoPoseSession.swift:1141`). The writer has its own queue and may drop a frame when the input is not ready. Live inference also drops frames while busy (`:895`). Recording cadence and analysis cadence are deliberately independent.
3. Live time is capture PTS minus the first received PTS (`:1161`). The shared SDK predictor runs on `inferenceQueue`; its callback returns through the main actor and a single `pendingFrame` slot (`:930`, `:1620`). Auto observes the most-confident person and locks after 60 analyzed poses with confidence ≥70, or 120 poses regardless. A changed exercise replaces the live pipeline; earlier live reps are not replayed into that new pipeline.
4. `CoreBridge.swift:24` converts the most-confident person. `AnalysisPipeline.process` computes exercise results, tracks any bells and records the frame. Live supplies no bell detections. The session publishes the HUD, crop, completed reps and framing hint; logs frames/reps; sends watch status and roughly one preview per second (`VideoPoseSession.swift:953`).
5. Done stops capture and finishes the recorder; it can recover a partial file. Rotation creates segments which are stitched before trimming (`:1287`). The **live** pipeline chooses the padded trim span. The resulting clip gets a fresh **offline** extraction/analysis and is stored as the final result (`:1336`, `:1439`). This is not “save the live pose track.” Live count is provisional; trim based on that provisional count is an existing coupling worth preserving until separately evaluated.

### Imported video and playback

Photos resolves an in-place URL where possible; otherwise a picker/file copy is used (`VideoPoseSession.swift:319`; `ContentView.swift:155`). The session installs a plain player item, waits for the model and compute plans, disables live inference and starts `OfflineAnalyzer.extract` (`VideoPoseSession.swift:508`).

The worker decodes through an orientation-applying video composition. For each sample it calls the SDK predictor, selects a person, optionally runs `BellDetector`, and appends a frame with observations but no exercise result. It drains autoreleased inference work per frame and reports a 60-frame heartbeat (`OfflineAnalyzer.swift:96`). Cancellation is forwarded to the detached worker at `:152`.

Auto detection or the selected/stored exercise chooses an analyzer; `AnalysisPipeline.analyze` learns static bell zones, runs the forward exercise/tracker pass, then fills missing bells backward. `fillRepImages` fetches checkpoint stills, `adopt` publishes the result, and `rememberCurrent` writes Recents (`VideoPoseSession.swift:578`, `:630`, `:756`, `:470`). A set folder contains `analysis.json`, rep JPEGs, a thumbnail and, for local sources, a clip; `index.json` contains the gallery summary. Photos sources use an identifier instead of copying the original video.

Playback does **no inference**: a display link looks up the nearest analyzed frame by player time (`VideoPoseSession.swift:879`). A periodic observer also publishes the playhead (`:156`); the view keeps a temporary scrub value while the user drags. The full-screen viewer shares the same player and analysis.

An explicit file trim shifts the existing analysis rather than extracting poses again; undo retains the earlier clip/pipeline/frames. Saving a trimmed Photos asset stashes the original, creates the replacement, deletes the original through Photos and changes the entry reference. These are platform transactions, not analysis operations (`:1344`, `:1409`, `:1466`).

### Open and launch refresh

`open(recent:)` first fetches the clip, loads its stored pipeline/images, and checks enabled model names. A newly required model triggers video extraction; fewer enabled models do not. Otherwise a stale analyzer stamp or qualifying Auto reclassification triggers pose replay (`VideoPoseSession.swift:357`).

`refreshStaleEntries` independently loads every stale entry, selects an exercise, replays frames, resolves the clip, fills images, then saves with the stored model names (`:188`). It does not rerun models. Although launched in a `Task`, its synchronous decoding and analysis run from a main-actor method; Photos/image awaits also allow other session work to interleave.

### Log → report → story → regression

The session log is operational evidence; it is not the stored analysis or the spec. A shake captures a screenshot and asynchronously requests a playhead still. Sending appends a context-bearing event and a separate `bugs.jsonl` record (`VideoPoseSession.swift:1515`, `:1585`). Watch events arrive via `WatchBridge`, MetricKit diagnostics via `CrashReports`.

`scripts/bugs-monitor.sh` polls for new reports; `file-bugs.sh` creates an issue once using the timestamp marker and attaches hosted images. Finding/creating the matching story, adding evidence to the issue, creating a fixture, fixing, verifying and closing are the documented developer workflow. The script does not automatically create the story or prove its acceptance criteria. Keep that separation. This review did not run the monitor, contact a device or file issues.

## What should stay

1. **An analyzer per exercise, with shared bookkeeping only.** The exercise rules differ materially. Bulgarian phases use body-height-scaled head travel; get-ups have long held stages; swings have ballistic duration rejection. A configurable universal state machine would obscure the measurements. Keep the small protocol and enum factory (`Exercise.swift:169`, `:27`).
2. **Replayable observations and fixture-first investigation.** `AnalysisPipeline.analyze` and the fixtures already take models and phones out of threshold experiments. Preserve that seam and strengthen it.
3. **Metadata-driven presentation.** The exercise owns phase/metric labels and gallery order. Get-up stages could grow without four bespoke galleries (`Exercise.swift:88`; `TurkishGetUpAnalyzer.swift:65`). Strings are adequate here; a large typed-metric migration is not warranted.
4. **Separate video display and extraction.** Plain `AVPlayerItem`, stored-track lookup, layer-frame zoom and decode-time trim preserve hard-won media behavior. Move these implementations cautiously, with no simultaneous rendering redesign.
5. **Photos identifiers and small local files.** The app does not need a database, cloud backend or repository abstraction hierarchy. A storage owner and safe update boundary are sufficient.
6. **Small bridge objects and value-driven leaf views.** `WatchBridge`, `PhoneLink`, `PhotosSuggestions` and the rep gallery already show useful boundaries. Keep transport separate from analysis and keep watch commands going through the same session actions as phone buttons.
7. **The evidence ladder and detector opt-in.** Commit `9552f70` and the detector notes report a full 3,989-frame phone pass at 43.7 fps and a flat 73 MB footprint after fixes. Commit `e376d5b` then disables the detector because its benefit did not justify the cost. Shared architecture must preserve both the device measurement and the ability to leave the feature off.

## Strains with code evidence

These are prioritized by correctness and verification cost. Static path mismatches are identified separately from runtime failures documented in history.

### 1. Observation and result are not distinct inputs

`FrameRecord` contains raw `bells`, derived `bell`, and derived `analysis` (`PoseTrack.swift:9`). `AnalysisPipeline.process` uses `extracted.bell ?? bellTracker.track(...)` (`AnalysisPipeline.swift:43`). Reopening and launch refresh feed saved **analyzed** frames back to this API (`VideoPoseSession.swift:194`, `:395`).

Consequently a saved non-nil bell is accepted rather than recomputed, and its frame does not advance the forward tracker. A tracker-version bump therefore does not mean “rerun today's tracker over every original observation.” Compact fixtures discard derived bells, so their normal replay path does not expose this discrepancy. This is directly visible in the code; the effect on a particular phone set has not been measured in this review.

The pipeline also represents both a mutable running machine and a restored result whose analyzer state is explicitly not restored (`AnalysisPipeline.swift:64`). Its `@unchecked Sendable` declaration (`:11`) does not express who may mutate it. Arrays of frames, pipeline frames, published reps and image-filled reps must be kept consistent by convention.

**Boundary to add:** observations-only replay input and a completed analysis result. Preserve the legacy stored shape at first; make conversion explicit. Restore may reuse a valid result; replay must derive new results from observations. One running engine has one owner.

### 2. Refresh policy and provenance are spread across callers

Launch Auto refresh retains the stored exercise unless a different result scores ≥70 (`VideoPoseSession.swift:196`). An opened stale entry calls `analyzeExtracted`, whose Auto branch always adopts the detector's winner (`:630`). A current entry uses the ≥70 gate before entering the same method (`:420`). These paths can choose differently from identical stored data. Commit `47ea972` documents an actual earlier manifestation: an opened stale get-up used the fixed Swing preference, while launch refresh already used its stored exercise.

Model names are read repeatedly by fully decoding snapshots (`RecentsStore.swift:197`, `:205`, `:213`). `rememberCurrent` stamps `loadedModels` even after pose-only replay or a shifted trim (`VideoPoseSession.swift:487`); launch refresh preserves the stored list (`:211`). A detector-off replay can thus relabel observations originally produced with the detector. Conversely, model names alone cannot distinguish a new export with the same bundle name, changed extraction thresholds or parser changes (`:84`). That matters because the week's investigation tried three materially different exports of the same checkpoint.

Story 035 promises a missing clip can open from stored analysis (`docs/stories/04-workouts.md:125`), but `open` returns on a missing URL before loading the snapshot (`VideoPoseSession.swift:378`). The data remains on disk; the requested fallback UI is not implemented by this path. Treat this as a story/implementation gap, not as evidence of data loss.

**Boundary to add:** one pure `RefreshPolicy` plus a request-local record of extraction provenance. Keep “next recording preference” separate from the stored set's exercise and from an explicit override of the open set.

### 3. A foreground operation has no stable identity across awaits

The session's `currentFileURL`, `currentEntryID`, `currentOrigin`, `extractedFrames`, `pipeline`, `rerunExercise` and `activity` are shared mutable fields (`VideoPoseSession.swift:79`, `:108`). File load, recent open, mode change, player metadata load, finishing a recording, trim/save and bug still extraction launch independent tasks. A main actor serializes individual accesses, but does not make all the work between awaits one transaction.

Concrete examples to characterize:

- The stored entry's analysis waits for stills, then `adopt` and `rememberCurrent` use session state that may have changed during the await (`:645`, `:668`). The exercise menu is outside the disabled controls container (`ContentView.swift:299`, `:355`), and watch commands have another entry path.
- Metadata loading for one player item asynchronously writes shared duration/frame interval without checking that the item is still current (`VideoPoseSession.swift:698`).
- The model-waiting file-load slot retains only the URL, discarding the original origin/date arguments (`:300`, `:236`).
- A canceled model rerun does not clear `rerunExercise`; only successful `finishAnalysis` consumes it (`:551`, `:590`). `analysisTask` cancellation covers a portion of the workflow, not every await or subsequent publication.
- After either success or cancellation, `analyzeAndPlay` unconditionally calls `play()` (`:568`). Story 028 says the canceled clip stays paused, and the smoke check checks timing/save events but not player state.
- `deviceRotated` appends completed segments asynchronously, while Done reads the shared segment array (`:1200`, `:1315`). This is an ordering risk to test, not a claim that a particular recording lost a segment.

**Boundary to add:** an immutable operation request and generation ID; owned tasks; terminal outcomes of completed/canceled/failed/superseded. Late progress, metadata and results must be ignored unless their ID is current. The job owns the target entry and provenance through saving. Do not rely solely on disabled buttons.

### 4. The app and Mac duplicate the difficult part of extraction

The app uses the SDK predictor and `CoreBridge` (`OfflineAnalyzer.swift:108`, `CoreBridge.swift:24`); `posetrack` directly creates Vision requests and parses pose tensors (`main.swift:120`, `:201`). Both separately configure oriented video reading. App extraction has a per-frame autorelease pool, cancellation bridge, completion-status check and heartbeat (`OfflineAnalyzer.swift:96`, `:143`, `:152`); the CLI loop has no enclosing per-frame pool, no equivalent terminal reader-status check, and only a 300-frame progress print (`main.swift:192`, `:218`). The bell detector's own inner pool is shared, so that portion is already protected.

The CLI pose parser assumes Float32 (`main.swift:124`), while the shared bell parser now handles Float16/Float32/Double (`BellDetector.swift:142`). This does not demonstrate a current Mac pose crash; it shows why the CLI cannot be assumed to validate every app parser behavior. CLI bells default to present-if-found (`main.swift:91`), whereas the app defaults to off (`VideoPoseSession.swift:272`). An unqualified speed comparison can therefore measure different model configurations.

**Boundary to add:** a shared sequential video extractor and explicit extraction configuration, initially retaining two pose adapters. Consolidate the pose adapter only after parity is demonstrated; a folder move cannot establish it.

### 5. Reports can describe a different computation from production

- App weight requires at least ten color-mapped frames (`VideoPoseSession.swift:463`); CLI weight accepts any nonempty vote (`main.swift:262`). Both independently implement the vote. Coasting copies a color with confidence zero, so the sampling population must be named rather than implied.
- CLI `POSETRACK_TRACE` uses a separate incremental tracker without whole-clip zones, person-height input or backward fill (`main.swift:174`, `:212`). Its comment suggests it previews what the pipeline will choose; final analysis now performs more work.
- The get-up raw-signal report independently calculates support elbow using the frame's overhead side (`TuningReports.swift:141`), while production uses the rep's majority-so-far side and filtered uprightness (`TurkishGetUpAnalyzer.swift:185`). Raw diagnostics are useful, but cannot be presented as the exact HUD signal.
- Bell report loss classes infer tracker gate reasons from output (`TuningReports.swift:410`). After backward fill, those categories are diagnostic heuristics rather than a record of actual forward decisions. The pre-existing research adds an inside-reps denominator that CLI output lacks.
- The initial Python trial picks the best wrist distance across rotations and does not apply the production visible-wrist gate (`scripts/model-trials/bell_trial.py:25`). It is candidate screening, not production parity.

**Boundary to add:** shared small metric functions and, where needed, structured diagnostics emitted by the actual decision. Preserve explicitly labeled alternative/raw experiments. “Near a wrist” is a proxy for bell tracking, not human-labeled detection accuracy; changing the denominator can change the headline percentage without improving a rep.

### 6. Persistence mixes expensive reads, publication and destructive replacement

`RecentsStore` is main-actor isolated and uses synchronous file reads, JSON encoding, JPEG loading/writing and clip copying (`RecentsStore.swift:73`, `:96`, `:213`). Opening/loading freshness information may deserialize an entire track several times. Launch refresh waits for video and thumbnails before publishing a count (`VideoPoseSession.swift:201`), so an iCloud fetch can hold up later entries despite pose replay needing no video.

`save` deletes duplicate entries before the replacement is fully written (`RecentsStore.swift:101`), removes the destination clip before copying (`:110`), then writes analysis, images and the index separately (`:117`, `:136`, `:291`). It creates a new entry without carrying `originalBackup` (`:130`). Failures can leave a partially updated set or lost backup metadata. These are static failure windows, not newly reproduced corruption reports.

**Boundary to add:** load one snapshot including metadata; a serial disk owner with an injectable root; stage a replacement before publication and retain the last valid set until success. Keep the same files and Photos-reference model. Exact multi-file recovery deserves its own small change; merely adding `.atomic` to each write would not make the whole transaction atomic.

### 7. The test ladder is strong below the orchestration seam and thin across it

There are 11 registered known-count fixtures, six marked `humanVerified` (`PoseTrackFixtures.swift:20`). The others are explicit regression baselines. Host tests check every count, phase-key completeness, score range, swing mirroring, geometry, frame status and watch JSON. Get-up tests pin stage order/windows. Bell tests cover association, rest/color/shape gates, coast/drop behavior, backward fill and legacy missing fields. Archived tracks assert nonempty input and print outcomes; they do not assert historical counts.

Specific gaps:

- `BellDetectorParseTests.swift:23` exercises row-format parsing across data types; it does not test the now-bundled dense format or NMS. Host tests can cover these without loading a model.
- `PoseTrackTests` checks frame retiming, but not nested completion/checkpoint retiming. `PoseTrack.shifted` retains `analysis` unchanged (`PoseTrack.swift:75`), while `AnalysisPipeline.shifted` separately shifts top-level reps (`AnalysisPipeline.swift:73`). A single result invariant is not currently checked.
- No host tests cover refresh policy, provenance preservation, operation supersession or storage failure. Those rules sit behind an initializer that immediately loads models, activates a watch, reads Documents and starts refresh (`VideoPoseSession.swift:128`).
- `scripts/pull-tracks.sh:30` exports poses and boxes **but drops raw bell sightings**. A phone bell problem cannot be reproduced from this export alone. CLI encoding, CLI old-fixture decoding and test decoding are also separate compact-schema implementations (`main.swift:228`, `:293`; `PoseTrackFixtures.swift:50`).
- `scripts/sim-smoke.sh` currently checks three exercise clips, trim and cancellation. Cancel allows under three seconds, whereas story 028 asks for one; it does not assert paused playback. The script's newest-log selection is not tied to a launch/job identity. Open/rerun/same-entry/HDR behavior is not all covered by this script just because a hook or historical manual check exists.
- `justfile:14` pipes host test output through filters without explicitly preserving the test exit status. `justfile:116` explicitly masks build failure before invoking the CLI, so an existing old binary may run. Commit `ab4f1a5` fixed the analogous device-build problem; the Mac recipe still has the risk.

**Boundary to add:** behavior tests for the decisions above, an observation codec, and reliable commands/log correlation. Add these where they prevent a specific regression, not a blanket coverage target.

### Smaller mismatches to keep separate from the architecture work

The documentation occasionally overstates what is checked: detection tests require ≥75 (`ExerciseCoreTests.swift:16`), while TESTING/analysis notes say ≥60. Pistol notes say working leg is reevaluated per rep; `SingleLegTracker` locks until reset (`PistolSquatAnalyzer.swift:264`), and rep completion does not reset it. Pistol transition input also permits the missing-knee sentinel to satisfy the descent comparison (`:122`), unlike the swing's explicit measured gate. These deserve fixtures and story decisions if pursued, not an opportunistic analyzer rewrite.

The log/bug boundary could capture immutable context at shake time: still generation starts at the shake, but `bugContext` and `session_t_ms` are read when the note is submitted (`VideoPoseSession.swift:1524`, `:1588`). A result can change while the report sheet is open. A `BugCapture` value would keep those pieces associated.

HDR behavior needs a preservation check, not automatic cleanup: `VideoLayerHostView` sets `clipsToBounds = true` (`ContentView.swift:693`) despite the blanket no-ancestor-clip instruction. This review did not observe the display; keep the existing implementation during unrelated moves and settle any contradiction with the documented phone instrumentation. Similarly, this is not an audit certifying the safety of the custom crash signal handler.

## What the week's changes teach

| History | Evidence and architectural implication |
|---|---|
| `4807cb2`, `681f98d`, `902e5cc` | Core extraction, fixture-driven Bulgarian tuning and the Mac tool created the right cheap analysis seam. Extend it. |
| `d269b25`, `47ea972`, `818d952`, `e376d5b` | Analyzer refresh, stored-exercise correction, model rerun, then subset semantics accumulated in separate session branches. Consolidate policy before adding another freshness rule. |
| `3b997e1` | Detector plumbing touched extraction, pipeline, persistence shape, CLI, overlay and reports. Cross-layer integration was necessary; several copies of conversion/configuration policy were not. |
| `42b50ff`, `ab4f1a5` | Tensor width and model export shape were distinct failures. Parser tests and full-clip model trials answer different questions. A shared library cannot substitute for either. |
| `9004020`, `1cd711e`, `241ebc7`, `9552f70` | Compute-plan sequencing, memory heartbeat, pixel-buffer retention, autorelease lifetime, startup readiness and idle-timer interruption needed different evidence. Give resource lifetime one owner and keep telemetry attached to the worker. The notes' causal explanations are historical diagnoses, not re-proven here. |
| `6aa97f9` | Detached-worker cancellation needed explicit propagation. A UI task reference alone was insufficient. Keep that fix and extend ownership through preparation/publication. |
| `85ed8e5`, `72439f4`, `be9c75d` | Coasting, distinguishing inferred confidence and backward fill evolved quickly under host/Mac evidence. Preserve deterministic raw-observation replay so stored sets benefit too. |
| `1233b25`, `93cb349`, `8309c6f`, `2376b1b` | HDR, decode-time trim, undo lifetime and Photos identity each carry learned platform constraints. These are the highest-risk code paths to “simplify” without their original verification. |

This history supports small boundary refactors. It does not support attributing every phone crash to the size of the session class, nor does it prove a new architecture would have prevented OS/model failures.

## Recommended target

### Module layout

Use the existing Swift package for **two library products** and the executable. Keep logical app components inside the current app target. Do not create a package per exercise or a separate watch-contract package now.

```text
ExerciseCore package
  ExerciseCore library
    Pose / FrameObservation / ObservationTrack
    existing analyzers, detector, skeleton and bell tracker
    AnalysisPipeline (running engine) -> AnalysisResult
    RefreshPolicy, extraction/analysis provenance values
    TrackCodec, shared report metrics
    FrameStatus / WatchStatus / WatchCommand

  ExerciseMedia library -> ExerciseCore
    VideoFrameReader + ClipExtractor
    pose inference adapter, BellDetector, BellColorSampler, ModelPlan
    ModelConfiguration / readiness / extraction telemetry

  posetrack -> ExerciseMedia + ExerciseCore
    arguments, model URL/cache setup, report formatting and fixture output

iOS app -> ExerciseMedia + ExerciseCore
  VideoPoseSession (small facade / session coordinator)
    AnalysisJobRunner
    PlaybackController
    RecordingController -> existing CameraSource / FrameRecorder
    StoredSetRefresher -> RecentsStore / disk owner
    Photos access + existing VideoFile operations
    BugReporter / SessionLog / WatchBridge
  SwiftUI views

watch app -> ExerciseCore
  existing PhoneLink + views + static complication
```

`ExerciseMedia` is explicitly for iOS/macOS Apple media APIs. The watch should not depend on it. Validate the package/target arrangement against the existing iOS/macOS/watch deployments when implementing; this review has not built that proposed graph. CoreGraphics value types and the current optional checkpoint images may remain in Core during migration. Removing them is not a prerequisite for useful ownership.

### Data contracts and analysis execution

`FrameObservation` contains source timestamp, oriented image size, selected-person pose/box, raw bell sightings, and enough extraction status to distinguish a valid empty detection from failure or a skipped optional stage. `ObservationTrack` carries those frames and their extraction provenance. It contains no completed reps or tracked-bell choice.

Keep `AnalysisPipeline` as the sequential mutable engine at first. Give it observations-only inputs and have it produce `AnalysisResult`: analyzed frames, reps, crop and analysis version. An in-memory compatibility adapter can expose the current `FrameRecord` to views. `restored` becomes loading a completed result, not manufacturing an apparently runnable engine with an empty state machine. No mutable engine crosses executors; the completed data does. Make actual value fields safely transferable before removing `@unchecked Sendable`, rather than adding that annotation to new containers.

Offline analysis has three explicit operations: learn static zones and track forward; fill eligible gaps backward; derive exercise phases/reps. Initially retain the exact current execution order because the exercise analyzers currently consume only poses. If bell-derived swing/get-up rules are ever approved, complete bell tracking before the exercise pass; that is a later behavior change with new fixtures, not part of this refactor.

Live analysis remains causal and may drop inference frames. Offline analysis sees the full clip and may use future frames. Share algorithms and contracts without pretending the two must give identical provisional outputs. Keep current timestamp semantics and frame-based thresholds; changing sample rate or replacing frame holds with elapsed time is separate tuning work.

### Extraction shared by app and Mac

`VideoFrameReader` owns AVAssetReader, oriented composition, sample timestamps and terminal status. `ClipExtractor` owns the sequential per-frame loop, one bounded pixel-buffer lifetime, pose/bell adapters, cancellation and telemetry. The pixel buffer is consumed and released within the iteration; compact observations survive. Avoid per-frame child tasks, unbounded async streams or multiple copies of loaded models on this memory-constrained app.

First move `BellDetector`, `BellColorSampler` and `ModelPlan` unchanged. Then put both existing pose paths behind a small `PoseInference` boundary. Keep the SDK implementation in the app adapter if the SDK is inconvenient to link on macOS. Share the reader/loop immediately; compare pose adapters on matched timestamps and sizes before choosing one. The eventual shared pose implementation must pass through the same letterbox/parser rules in both app and CLI. Treat replacing the SDK live predictor as a separate, optional migration with phone checks.

Every extraction uses an explicit configuration: enabled models, artifact/export revision, pose confidence, detector floor/cap/NMS settings, color-sampling revision and extraction/preprocessing revision. Record a small stable build-time manifest or explicit revision string; runtime hashing of multi-megabyte models per frame is unnecessary. Device/compute-unit choice belongs in diagnostic metadata too, without automatically invalidating observations for every hardware change.

A model owner handles readiness once and ensures preparation/compute-plan work does not overlap inference on the same instances. Foreground camera and offline jobs coordinate access. Keep a serial worker/queue where blocking framework calls require it; simply placing a synchronous long loop in an actor would not itself make cancellation responsive.

### One refresh decision

`RefreshPolicy` is a pure function of stored metadata, request intent, mode/detection, current derivation version and required extraction configuration. It returns `restore`, `replay(chosenExercise)`, `extract(chosenExercise/config)`, or `unavailable(reason)`. A missing video prevents extraction, not viewing available stored results. A launch refresh can replay without video and defer image enrichment.

Recommended behavior to pin before routing both callers through it:

| Situation | Decision |
|---|---|
| New import, fixed mode | Extract, then analyze that chosen exercise. |
| New import, Auto | Extract, then use the detector winner and report confidence, preserving present import behavior. |
| Explicit exercise override of the open set | Replay existing observations as the selected exercise; preserve set ID and extraction provenance. |
| Existing set, stale analysis, fixed next-recording mode | Replay as the stored exercise. |
| Existing set, Auto | Change stored exercise only when the new winner differs and confidence is ≥70; use this rule on open and at launch. |
| Same required extraction configuration and current analysis | Restore; no model run. |
| Newly enabled model or changed required model/export/extraction revision | Extract from video when opened; retain the old result until success. |
| Optional detector disabled but stored data includes it | Keep existing observations/provenance; no extraction solely to remove information. |
| Video unavailable | Display stored analysis with unavailable playback; permit pose replay from valid observations; do not stamp a model rerun as completed. |

The unified ≥70 rule for stale Auto sets and missing-video display close observed inconsistencies; they are **proposed behavior decisions**, not mechanically equivalent moves. Pin current behavior first, then make each chosen correction separately with its story. Persisting a durable manual-override lock across all future Auto opens is another product decision; do not invent it in this refactor.

Keep two kinds of freshness: **extraction provenance** changes only when observations are regenerated, and **analysis version** changes when those observations are replayed. A stored set may legitimately have more optional observations than the running build would newly produce. Keep `AnalysisVersion.current` and its bump rule; a version vector per exercise is unnecessary now.

### App ownership and publication

Keep `VideoPoseSession` as a compatibility facade while extracting components. A request holds `{operationID, entryID, clipReference, origin, recordedAt, exerciseIntent, extractionProvenance}`. The session owns at most one foreground operation. Starting another cancels/supersedes the earlier one and waits for shared model access to be released; worker progress and publication are checked against the ID. A canceled operation neither saves nor autoplays. A completed operation publishes a coherent loaded-set value.

Use a small session enum such as idle / recording / reviewing, with a separately owned optional foreground job. Published flags like `canCancelAnalysis`, `canSave` and display labels derive from those values where practical. Keep scrub focus, zoom and sheet state in the views. Do not build a reducer framework or duplicate every flag in a second store.

`PlaybackController` owns the player, observers, display link, current-item identity and navigation. `RecordingController` owns camera, recorder, segment completions, live engine and in-flight inference association. Existing queue implementations stay intact initially. Move `VideoFile` helpers physically if useful, but preserve keyframe/HDR/Photos behavior. `WatchBridge` and phone controls invoke the same facade commands; watch status is derived from the authoritative recording state.

`StoredSetRefresher` works one set at a time, below foreground work. Serialize commits by entry and compare a revision before replacing data so a late background refresh cannot overwrite a newer manual override/trim or recreate a deleted set. Pure replay can occur away from the main actor; publish counts before optional Photos/image work. `RecentsStore` remains the observable index facade over a small disk owner, with one snapshot read per operation and a root URL injectable for tests.

`BugReporter` takes an immutable `BugCapture` at shake time and later adds the user's note. Screenshot capture stays on the main actor; still extraction and writing do not need the whole session. Keep JSONL and the current event names. Add job/set IDs to extraction/analysis events so smoke checks, reports and logs correlate a specific operation. Use small typed progress/completion payloads at new boundaries and adapt them into the existing log; do not rewrite the full event catalogue into a telemetry framework.

### Shared measurements

Add only measurements with real multiple consumers: a `BellMetrics` result with explicit visible-wrist denominator, observed-at-hand count, held-at-hand count, inferred count, and optionally inside-detected-reps counts; one color-weight vote with a named minimum-evidence rule. App and CLI should use the same weight policy unless a CLI experiment explicitly overrides it.

Reports should render production `ExerciseFrameResult.metrics` for “what the HUD used,” and label independently computed signals as raw. Emit a compact tracker decision reason only when a tuning/report sink requests it; this avoids reconstructing gate decisions after backward fill. Keep research-only algorithms and threshold sweeps in tests/lab helpers. Do not promote the pre-existing attachment/size experiments into the product as architectural cleanup.

## Migration, cost and stopping points

Estimates assume one engineer familiar with this code, existing fixture/model assets available, and no unrelated feature work. They include focused tests and documentation; device availability can stretch calendar time. These are independent reviewable changes, not one commit combining unrelated fixes. An issue-backed correction still gets its own commit and the documented close-after-phone workflow.

| Step | Work and benefit | Estimate | Risk, verification and safe stopping point |
|---|---|---:|---|
| 1 | Add an observation-only adapter/type and shared compact codec; separate restore from replay; preserve raw bells in archive export. Make current-tracker replay testable from saved data. | 1–2 days | Legacy decoding and trim timestamps. Host: legacy fixtures, raw-bell round trip, deliberately stale derived bell, unchanged rep/phase/score outputs and trim invariants. Keep on-disk schema initially. Stop with existing callers/views still working. |
| 2 | Extract `RefreshPolicy` and route open/launch through it; preserve provenance and same-entry identity. Separate the two proposed policy corrections from mechanical extraction. | 1 day | Existing semantics differ, so characterize before changing. Host table tests; simulator stale-open/launch, fixed-mode get-up, model subset, second-open/no-run and missing-clip result. Stop with one policy behind current session methods. |
| 3 | Request-local context, foreground job identity, preparation/cancellation/terminal outcomes, guarded publication and model access. | 2–3 days | Late callbacks and cancel timing. Fake completions in controlled order; cancel while preparing/extracting/filling stills; A-then-B load; failed rerun then fresh import. Simulator checks no save/play after cancel and no stale adoption; phone long pass and recording-to-review. Stop with the current facade and UI intact. |
| 4 | Add `ExerciseMedia`, move shared detector helpers, unify reader/loop/telemetry, then demonstrate and consolidate pose-adapter parity if feasible. Fix command exit-status masking before trusting comparisons. | 3–5 days | Highest parity/resource risk. Host tensor tests including dense/NMS; Mac full/blank/rotated clips with explicit identical configs; simulator wiring; phone memory and timing. If pose adapters cannot safely converge, stop with a shared loop and two documented adapters. |
| 5 | One-read snapshot API, injected storage root, serial disk writes, staged replacement, revision checks and background refresh independent of image fetch. | 1–2 days | Persistence recovery and Photos/backup identity. Host codec/policy tests; temporary-directory storage tests in an appropriate target; simulator save/open/failure paths; phone Photos replacement/undo. Stop retaining the current file layout and old reader compatibility. |
| 6 | Extract playback, recording and bug-capture owners as needed; narrow leaf-view dependencies; shared report metrics and actual decision traces. | 2–3 days | Camera queue/segment ordering, player observers and report association. Host metrics/command tests; simulator screenshots/trim; phone rotation, HDR, music, watch and shake flow. Stop after each owner; cosmetic view/file rearrangement is optional. |

Total: **10–16 engineer-days**; first three: **4–6**. Narrow a step if it reveals an unexpected behavior change. Roll back code moves through their compatibility facades; keep old snapshots readable. Avoid destructive data migration as a prerequisite. Do not promise byte-identical JSON ordering, pixel-identical hardware inference, or faster neural inference from these refactors.

## Verification after adoption

No rung was run for this read-only review. For implementation, use the cheapest rung that can actually observe each change, then use the phone for platform behavior. Preserve the familiar commands after correcting their exit-status handling.

| Change | Required evidence |
|---|---|
| Analyzer/skeleton rule | Failing fixture first, host regression and relevant TuningReports numbers; update the exercise Experiments entry and `AnalysisVersion`; story names the eventual commit and verifying rung. |
| Tracker rule | Host raw-observation replay, empty frames, coasting/inferred confidence, backward fill, stored-result replay, positive fixtures and no-bell controls. Report seen/held and inside-rep denominators. Phone with detector explicitly enabled for overlay behavior. |
| Detector/parser/model | Host synthetic dense/row tensor shapes, precision/strides/NMS/empty results; Mac **full clips** before app integration, including the long get-up and blank/no-bell controls. Then simulator wiring and phone memory/ANE cost. Bump analysis version per repo rule and extraction revision when observations change. |
| Extraction refactor | Same explicit models/configuration, timestamp/frame count and oriented image size comparisons, pose/box deltas with a documented tolerance, unchanged counts/checkpoint windows. Compare source code revisions and built binary before trusting performance. Phone checks buffer lifetime; Mac parity does not establish it. |
| Stored-set policy/storage | Restore/replay/extract decision table; preserve ID/provenance/Photos and backup references; stale open equals launch refresh; canceled/failed jobs retain last valid result; deleted/updated entry rejects late refresh commit. |
| Session jobs | Deterministically complete jobs out of order; verify only current job may publish/save/play. Existing real-reader cancel smoke, strengthened to check the paused result and story timing. |
| Playback/trim | Host full timestamp invariants, simulator passthrough and first displayed frame from the same job/item, phone HDR trim and undo. Never attach extraction output to the player. |
| Camera/watch/Photos/audio/report | Phone and watch: camera cycle, rotation/Done ordering, music continuity, idle behavior during a long pass, Photos replacement/undo, preview/status freshness and shake evidence. Install the watch separately when changed. |

Success is observable: a tracker change replays saved observations without model work; opening and background-refreshing a set make the same choice; the Mac tool and app name the same extraction configuration and execute the same loop; cancellation cannot later publish a result; a report's numbers come from the production result or are clearly labeled experimental. The interface should feel the same at the gym. Those outcomes, rather than a target line count, decide whether the refactor paid for itself.
