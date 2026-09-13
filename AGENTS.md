# Agent instructions: Exercise Analyzer

iOS app (SwiftUI + Core ML pose model) that counts and scores kettlebell swings, pistol squats, Bulgarian split
squats and Turkish get-ups. `ExerciseCore/` is the platform-free analysis package; `ExerciseAnalyzer/` is the app;
`ExerciseAnalyzerWatch/` the watch companion.

## Read these before working

| File | What it settles |
|---|---|
| [docs/TESTING.md](docs/TESTING.md) | the test ladder (host → Mac model → simulator → phone), fixtures, simulator launch hooks, which change is verified where |
| [docs/DEBUGGING.md](docs/DEBUGGING.md) | the session log and every event type, pulling logs, the bug monitor loop, filing and closing reports, device tooling |
| [docs/analysis/README.md](docs/analysis/README.md) | how poses become phases, reps and scores; one file per exercise with thresholds, fixtures and the experiments behind every rule |
| [docs/stories/README.md](docs/stories/README.md) | the spec: user stories per journey, each with its status and commits |

## Rules

- **Test ladder**: host `just test` (~1 s) → simulator `just test-sim` (5–8 min) → phone `just run-device`. Verify on
  the cheapest rung that can see the change and say which rung you used. The simulator runs the model on the CPU
  (~20 fps); it has no camera, no HDR, no taps: drive it with `SIMCTL_CHILD_SWING_*` hooks and wait on log events
  ([TESTING.md](docs/TESTING.md)).
- **Bump `AnalysisVersion.current`** (ExerciseCore/Sources/ExerciseCore/AnalysisVersion.swift) in any commit that
  changes an analyzer, the detector, or the skeleton math: stored sets re-analyze themselves against it (#19).
- **Analysis notes live in `docs/analysis/`**. Read the exercise's file before touching its analyzer; every rule
  change adds an Experiments entry there (date, fixture, the numbers that decided it, the commit), and a
  `TuningReports` report that prints those numbers is the preferred evidence.
- **Wrong rep count = fixture first.** Export the set's pose track from the phone's `Documents/recents/<id>/analysis.json`
  into `ExerciseCore/Tests/ExerciseCoreTests/Fixtures/`, make `swift test` fail, then fix. Never tune by reinstalling.
  Mark fixtures `humanVerified` only when Igor confirmed the count.
- **Instrument before theorizing.** For any phone-only symptom add a log event, deploy, `just pull-logs`, then fix
  from evidence. Never ship a second guessed fix ([DEBUGGING.md](docs/DEBUGGING.md) lists the events).
- **Run the bug monitor while Igor is on the phone**: arm a `Monitor` on `scripts/bugs-monitor.sh` (persistent).
  It polls the phone every minute and emits one line per new report, so the agent is woken only when there is
  something to file; a `/loop 5m just bugs-check` wakes the model every five minutes to look and is the fallback
  when Monitor is unavailable. On an event: `just pull-logs && just file-bugs`, then for every report find or
  write the story in `docs/stories/` that covers
  it before fixing anything (a request becomes a story, a bug gets an `Issues:` line, no story means the spec has a
  hole). Evidence and analysis go on the issue as a comment. A bug Igor reports by voice gets an issue too. The whole
  flow: [DEBUGGING.md](docs/DEBUGGING.md).
- **Every feature or behaviour change updates the user stories** (`docs/stories/`) in the same commit or the
  next: a new capability gets a story in its journey (Cohn + Gherkin, `user-story` skill) with a `Status:` line
  naming its commit and where it was verified; a changed behaviour edits the story's acceptance criteria and adds
  its commit to the `Status:` line. Status lives only on the stories. No story, not done.
- **One commit per issue**, referencing it. Close the issue once the fix is on the phone (`Fixes #N` in the commit
  when the verifying rung already ran, otherwise close it by hand after `just run-device`) with a comment saying
  what was verified where and what Igor should feel; Igor reopens if it is not fixed. Never leave a fixed bug open.
  Never bundle fixes. Never `git add -A` (`.build/`, `Build/`, `.claude/worktrees/` must stay untracked).
- **Analyzer semantics** (details and evidence in `docs/analysis/`): a swing rep is top→top, about 1.2 s, over 4 s is
  the walk-in or setup and is discarded; an upswing over 1 s is not a swing; unmeasured joints read 0° and must not
  drive transitions; joints are chosen per frame by the confident side, not by label. Bulgarian phases run on head
  height (the front knee bends too little from a diagonal camera). Get-ups need ≥3 s up and ≥2 s down and record the
  overhead arm.
- **Video**: never transform, clip, or attach a pixel output to the `AVPlayerLayer` or its ancestors (HDR washout);
  zoom by resizing the layer frame. Trim is passthrough from the previous keyframe's *decode* time; a time-ranged
  `AVAssetReader` emits empty sync-flagged placeholder samples to ignore.
- **Audio session** stays `.ambient` + `.mixWithOthers`: the app never interrupts music.
- **Device tooling**: builds need the sandbox off and `-allowProvisioningUpdates -allowProvisioningDeviceRegistration`,
  never `-sdk` (breaks the watch target). "No provider was found" is noise. A locked phone fails launch, not install.
  Install the watch app separately when the watch target changed ([DEBUGGING.md](docs/DEBUGGING.md)).
- **Background agents** that investigate are read-only, in a worktree, notes under `~/tmp/agent/notes/`; confirm scope
  before an agent that writes to the repo. Reap background commands when done.
- **Gym-first UI**: few large targets, HUD on the video, Recents point at Photos. Propose with a numeric plan or a
  trade-off table, then one "do it".
