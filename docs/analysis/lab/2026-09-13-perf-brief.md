# Brief: performance of the offline pass with the bell detector on (exercise-analyzer)

Igor: "How much performance hit did I pay for my improvements? Use Codex to find optimization improvements."
You are Codex, in your own git worktree of the repo (branch codex-bell). Read AGENTS.md first. Never commit or
push; edit only with your file-edit tools. Notes go to `/tmp/bell-lab/perf-codex.md` (your sandbox cannot write
`~/tmp`). Memory on this Mac is tight tonight: run at most one heavy process at a time, prefer the short
`swing-sample-4reps.mp4` clip (165 frames) for any posetrack timing, and never run the two-minute get-up clip.

## What changed tonight (commits on main: 85ed8e5, 72439f4, be9c75d, fd97209, a6a2cf5)

- `BellDetector`: `minConfidence` 0.25→0.15 and `maxSightings` 6→12 (more anchors pass the floor, up to six more
  colour samples a frame through `BellColorSampler.averageColor`).
- `BellTracker`: new gates (start distance, follow confidence, coasting on velocity, a flat-box start gate, a head
  keypoint veto, a nearest-wrist tie-break), all pure Swift per frame.
- `AnalysisPipeline.analyze`: a second tracker pass run backward over the whole track (`BellTracker.filledBackward`)
  and the tracker now runs on frames with no sighting too.
- The phone's offline pass (`ExerciseAnalyzer/VideoPoseSession.swift`, the pass around line 600–700) decodes a
  frame, runs the pose model, then the detector, samples colours, and hands `FrameRecord`s to the pipeline; it logs
  `offline_progress` every 60 frames (pose_ms, bell_ms, decode_ms, fps) and `offline_pass` at the end (fps,
  avg_infer_ms, bell_avg_infer_ms). The last phone numbers with the detector on, before tonight: IMG_4342, 3989
  frames, 91 s at 43.7 fps, detector 12 ms a frame, memory flat at 73 MB (docs/analysis/kettlebell-detector.md).

## Your job

1. Read `BellDetector.swift` (parseDense over 8400 anchors, suppressOverlaps, the Vision request per frame),
   `BellColorSampler` (wherever it lives in ExerciseCore/Sources), `Bell.swift`, `AnalysisPipeline.swift`, and the
   offline pass in `VideoPoseSession.swift`. Find where the per-frame time and memory go with the detector on, and
   what tonight's changes added. Be concrete: which loop, how many iterations, what allocates.
2. Measure what you can on the Mac cheaply: `swift test --filter TuningReports/testBellTrackerHeldPerFixture`
   timing (the tracker and the backward pass over all five fixtures), and
   `ExerciseCore/.build/release/posetrack ~/tmp/agent/swing-samples/swing-sample-4reps.mp4 --model
   ExerciseAnalyzer/yolo26n-pose.mlpackage --exercise kettlebell-swing --bell-model
   ExerciseAnalyzer/yoloe-26n-kettlebell.mlpackage` (prints fps) with the defaults against `--bell-conf 0.25` and
   `POSETRACK_BELL_MAX=6` (the old detector settings), three runs each, median. Build the release binary first
   with `swift build -c release --product posetrack` in ExerciseCore if it is missing in your worktree.
3. Write `/tmp/bell-lab/perf-codex.md`: a table of where the milliseconds go per frame (measured or estimated,
   say which), the cost of tonight's changes, then ranked optimisation proposals, each with the mechanism, the
   expected saving on the phone, the risk to the numbers (held %, controls), and the code it touches. Prefer
   boring wins (fewer allocations, no per-frame Vision request re-creation if that is what happens, vectorised
   parse, cheaper colour sampling, skipping the detector on frames the tracker does not need) over clever ones.
   Do not implement anything; Claude runs Instruments locally and decides.
4. Finish by printing the table and the top three proposals.
