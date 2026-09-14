# Exercise Analyzer

An iPhone and Apple Watch app that watches you lift. Point the phone at yourself, or hand it a clip, and it
counts your reps and scores your form for kettlebell swings, pistol squats, Bulgarian split squats and Turkish
get-ups. The pose model runs on the phone; nothing leaves it.

| The phone: the HUD over the video, the rep gallery below | The wrist: framing the shot before you record |
|---|---|
| ![Swing analysis: rep count, phase pills and joint angles over the video, rep gallery below](docs/screenshots/swing-analysis.png) | ![Watch preview: the camera picture with the in-frame capsule and Record, Camera, Cancel](docs/screenshots/watch-preview.png) |

Every screen, phone and watch: [the gallery](docs/screenshots/README.md).

## What it does

The user stories are the spec. Each one says what the feature does, how it is verified, and which commit
built it, so the list below is short on purpose.

- **Record a set.** Live camera with the rep count, the phase and the joint angles drawn over you as you go.
  Done trims the clip to where the reps were and runs a second, slower pass over every frame. That pass is
  the truth: the count, the scores, and the gallery come from it. [Recording](docs/stories/01-recording.md)
- **Look at it afterwards.** Scrub the clip with the skeleton on it, step by rep, by position, or by frame,
  and open a gallery of stills cut to you, one row per rep. Hold the middle of the picture and both sets of
  keys appear under your thumbs. [Reviewing](docs/stories/02-reviewing.md)
- **Bring your own clip.** Import from Photos or Files, trim it, save the trimmed version back.
  [Clips](docs/stories/03-clips.md)
- **See the day.** A sheet of the day's sets, collapsed to a line of stick figures or open to the full
  gallery, with recents that point back at Photos. [Workouts](docs/stories/04-workouts.md)
- **Run it from the watch.** The whole session from the wrist, phone on a tripod. See below.
  [From the wrist](docs/stories/05-watch.md)
- **Tell us what broke.** Shake the phone and a report goes out with the clip, the playhead and the log
  attached. [Feedback](docs/stories/06-feedback.md)

## From the wrist

This is how I actually use it. The phone goes on a tripod or a rack, I walk to where I lift, and the watch
does the rest. **Preview** shows me the camera picture on my wrist, tells me if my feet are cut off, and lets
me flip to the wide lens without walking back. **Record** starts the set from that moment. The count and the
time sit on the picture, Pause freezes them, Done ends the set, and the wrist taps me when I drift out of
frame. When the set is over the watch shows the final count and starts counting my rest. Lower the wrist and
the watch face keeps showing the set.

The watch never pretends the phone is there when it is not: lose the connection and it says so, with the last
count it heard. There is no workout session and no heart rate on purpose; the watch is a remote control, not
a fitness tracker.

Every watch screen and what it must show and offer, plus the stories behind each control, are in
[docs/stories/05-watch.md](docs/stories/05-watch.md).

## How it works

A YOLO pose model finds seventeen keypoints in every frame. Per-exercise analyzers turn joint angles into
phases, phases into reps, and reps into scores, each with thresholds that were tuned against real clips and
the fixtures that prove them. The live pass feeds the HUD; the offline pass over the recorded clip decides.

- How poses become reps and scores, one file per exercise: [docs/analysis/](docs/analysis/README.md)
- What the offline pass costs and how it is measured: [performance](docs/analysis/performance.md), and every
  precision and speed hypothesis we tried, with its numbers: [optimization](docs/analysis/optimization.md)
- The kettlebell detector, off by default until it earns its keep: [kettlebell-detector](docs/analysis/kettlebell-detector.md)
- Where the code is going and why: [docs/architecture/](docs/architecture/)

## Build and test

```bash
just model        # fetch the pose model into the app (gitignored)
just test         # host tests on real pose tracks, about a second
just build-sim    # simulator build
just test-sim     # the app end to end on the simulator, judged from its log
just watch-screens  # every watch screen from a fixed state, for your eyes
just run-device   # your iPhone, with the watch app installed alongside
```

The test ladder, the fixtures, the simulator hooks and which change is verified where:
[docs/TESTING.md](docs/TESTING.md).

## Debugging

Every launch writes a session log to the phone. Shake to file a bug with the context attached, then
`just pull-logs` and `just file-bugs` turn the reports into GitHub issues. The event catalogue, the device
tooling and the bug monitor loop: [docs/DEBUGGING.md](docs/DEBUGGING.md).

## Layout

| Directory | What lives there |
|---|---|
| `ExerciseCore/` | The analysis package: skeleton math, analyzers, the offline pass, fixtures and tests. No UIKit. |
| `ExerciseAnalyzer/` | The iPhone app: camera, recording, playback, the HUD, the galleries, the watch bridge. |
| `ExerciseAnalyzerWatch/` | The watch app and its face complication. |
| `ExerciseAnalyzerControls/` | The lock-screen control that opens the app on Live. |
| `docs/` | Stories, analysis notes, testing and debugging guides, screenshots. |

Working on it with an agent? Start at [AGENTS.md](AGENTS.md).
