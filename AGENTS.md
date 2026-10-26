# Agent instructions: Exercise Analyzer

iOS app (SwiftUI + Core ML pose model) that counts and scores kettlebell swings, pistol squats, Bulgarian split
squats, split squats, Turkish get-ups and pull-ups. `ExerciseCore/` is the platform-free analysis package; `ExerciseAnalyzer/` is the app;
`ExerciseAnalyzerWatch/` the watch companion.

## Read these before working

| File | What it settles |
|---|---|
| [VISION.md](VISION.md) | what this app is and isn't: who it serves, what it owns, and the lines it does not cross |
| [docs/TESTING.md](docs/TESTING.md) | the test ladder (host → Mac model → simulator → phone), fixtures, simulator launch hooks, which change is verified where |
| [docs/DEBUGGING.md](docs/DEBUGGING.md) | the session log and every event type, pulling logs, the bug monitor loop, filing and closing reports, device tooling |
| [docs/analysis/README.md](docs/analysis/README.md) | how poses become phases, reps and scores; one file per exercise with thresholds, fixtures and the experiments behind every rule |
| [docs/stories/README.md](docs/stories/README.md) | the spec: user stories per journey, each with its status and commits |
| [docs/analysis/performance.md](docs/analysis/performance.md) | how the offline pass is measured (Mac A/B, `sample`, the instrumented run) and what each change cost |
| [docs/analysis/optimization.md](docs/analysis/optimization.md) | index of every precision and speed hypothesis, with its numbers |
| [docs/architecture/](docs/architecture/) | the 2026-09-13 architecture reviews (Codex, Fable) and the decision: keep the core, take `VideoPoseSession` apart in small steps. Steps 1–4 (StoredSetPlan, index metadata, OfflineJob, ModelSet) shipped under #52, closed; of step 5, 5d (BugReporter) and 5a (`LoadedClip`, the clip on screen as one value) are done, 5c (ClipEditor) and 5b (CameraRecorder) are not started (#176, they need the phone) and the file is still ~3,100 lines; the parked full plan is #51. Also the 2026-09-26 worktree decision for outside agents, and the 2026-10-26 proposal (not yet decided): a set's facts carry their provenance, and a cross-day history with a JSON export |

Lab notebooks (hypotheses, predictions, numbers, rejected ideas) live in `docs/analysis/lab/`; the analysis notes
carry only what was decided.

## Rules

- **Beads track the work** (Igor, 2026-10-17). Run `bd prime` at the start of a session and after context recovery,
  then `bd ready`. Create a bead before new work, mark it `in_progress`, close it with a one-line reason when the
  work has merged; a decision only Igor can make gets the `needs-igor` label. GitHub issues stay the intake for
  reports (the bug-kit listener files them) and the place evidence goes; a bead names its issue. The issues live
  in Dolt, not in code branches: `.beads/config.yaml` and `.beads/metadata.json` are tracked configuration, and
  `bd dolt push` / `bd dolt pull` sync the data through this repo's `refs/dolt/data`. Every worktree shares the
  main checkout's database. No beads git hooks: the no-mistakes gate owns the commits.
- **Test ladder**: host `just test` (~1 s) → simulator `just test-sim` (5–8 min) → phone `just run-device`. Verify on
  the cheapest rung that can see the change and say which rung you used. The simulator runs the model on the CPU
  (~20 fps); it has no camera, no HDR, no taps: drive it with `SIMCTL_CHILD_SWING_*` hooks and wait on log events
  ([TESTING.md](docs/TESTING.md)). Never run `just test-sim` while another `xcodebuild` (a signed device or
  watch build) is running: the checks' startup waits fail under contention and a check can read the previous
  clip's result; treat such a run as failed and rerun it once the build is done. **Only one simulator on this Mac
  at a time** (Igor, 2026-10-11): before booting, check `xcrun simctl list devices booted` and wait until it is
  empty; shut yours down when done, failed runs included. A paired watch and phone count as two. The no-mistakes
  test agent boots nothing (`test.instructions` in `.no-mistakes.yaml` keeps it on the host rung): live checks are
  the driving session's, once, in its build turn, recorded in the PR body. A new
  model (a detector, a bigger pose model) is tried on the Mac first with Core ML over the sample clips
  (`scripts/model-trials/`), never straight in the app.
- **Bump `AnalysisVersion.current`** (ExerciseCore/Sources/ExerciseCore/AnalysisVersion.swift) in any commit that
  changes an analyzer, the detector, or the skeleton math: stored sets re-analyze themselves against it (#19).
- **Analysis notes live in `docs/analysis/`**. Read the exercise's file before touching its analyzer; every rule
  change adds an Experiments entry there (date, fixture, the numbers that decided it, the commit), and a
  `TuningReports` report that prints those numbers is the preferred evidence.
- **Wrong rep count = fixture first.** Export the set's pose track from the phone's `Documents/recents/<id>/analysis.json`
  into `ExerciseCore/Tests/ExerciseCoreTests/Fixtures/`, make `swift test` fail, then fix. Never tune by reinstalling.
  Mark fixtures `humanVerified` only when Igor confirmed the count.
- **Video frames go to a cheaper vision helper first** (Igor, 2026-09-20). Always delegate frame inspection
  during video investigations to an available lower-cost vision model, in a fresh context with just the paths,
  timestamps and question. The main agent works from its concise text descriptions, not batches of images.
  This authorizes a read-only frame-description subagent; use the worktree rules below. Sample coarsely first,
  then inspect short sequences around disputed events; cache the descriptions and reuse them. Preserve timestamps,
  evidence paths, occlusions and uncertainty. A still does not establish a completed rep, and a model's count
  never makes a fixture `humanVerified`. Ask the helper for more evidence when unclear; inspect individual frames
  in the main agent only when specifically needed to resolve a remaining ambiguity or requested by Igor.
  The workflow is shared with Claude through `CLAUDE.md`; model selection is specific to each agent's tooling.
  See [the frame-description workflow](docs/DEBUGGING.md#video-frame-descriptions).
- **Instrument before theorizing.** For any phone-only symptom add a log event, deploy, `just pull-logs`, then fix
  from evidence. Never ship a second guessed fix ([DEBUGGING.md](docs/DEBUGGING.md) lists the events).
- **The bug-kit listener files every report and crash** (Igor, 2026-10-11): it is always on in a Herdr pane
  (bug-kit's `listener/bug-listener`, every five minutes, every paired iPhone and iPad), pulls each new report,
  opens the issue and appends a line to `~/tmp/agent/bugs/inbox.jsonl`. Never file reports yourself: `just file-bugs`
  next to it files them twice. While Igor is on the phone, arm a `Monitor` on `scripts/bugs-monitor.sh`
  (persistent): it tails that inbox for this app and prints one line per filed issue, plus `listener_stale` when
  the listener has stopped polling. On an event: read the issue, `just pull-logs` for its log, then for every
  report find or write the story in `docs/stories/` that covers it before fixing anything (a request becomes a
  story, a bug gets an `Issues:` line, no story means the spec has a hole). Evidence and analysis go on the issue as
  a comment. A bug Igor reports by voice gets an issue too. The whole flow: [DEBUGGING.md](docs/DEBUGGING.md).
- **A bug in BugKit code is fixed in BugKit, not here.** Bug reporting is the shared package
  [idvorkin/bug-kit](https://github.com/idvorkin/bug-kit) (its README, "Where a bug gets fixed"): the dialog, the
  shake, dictation, the store and its format, crash capture, pruning, What's new, the listener and the scripts are
  its code. A bug there is filed there, fixed test-first on a branch there, PR'd, and then BugKit is bumped here.
  Until then, work around it only through BugKit's hooks or options, with a `ponytail:` comment naming the bug-kit
  issue, never by copying its code in. Bugs in our own hooks (`ExerciseAnalyzer/BugReport.swift`: the screen, the
  context, the frame) stay here. Shared practices for all apps live in
  [idvorkin/bug-kit](https://github.com/idvorkin/bug-kit) (README: "Shared practices for every app"); a practice
  that applies to every app is filed there, and our issue links to it (Igor, 2026-10-13).
- **Every feature or behaviour change updates the user stories** (`docs/stories/`) in the same commit or the
  next: a new capability gets a story in its journey (Cohn + Gherkin, `user-story` skill) with a `Status:` line
  naming its commit and where it was verified; a changed behaviour edits the story's acceptance criteria and adds
  its commit to the `Status:` line. Status lives only on the stories. No story, not done.
- **One commit per issue**, referencing it. Close the issue when its fix merges to main (Igor, 2026-10-13; it
  used to wait for the phone): at once, with a comment naming the merge commit, what was verified where, what
  Igor should feel, and any device check still pending as "to verify on device"; Igor reopens if it is not
  fixed. Never leave a fixed bug open.
  Never bundle fixes. Never `git add -A` (`.build/`, `Build/`, `.claude/worktrees/` must stay untracked).
- **Every change goes through the no-mistakes pipeline** (Igor, 2026-10-10). The gate is installed in this repo:
  commit on a feature branch, `no-mistakes axi run --intent "<what Igor set out to do, with the decisions>"` (or
  push to the no-mistakes remote), answer its gates, and when it reaches `checks-passed` merge the PR yourself
  (delete the branch, verify `origin/main`). Do not wait for PR feedback: nobody gives it, the pipeline is the
  review. Never block on CI (Igor, 2026-10-13): once review and test have passed and the run only waits on CI
  checks, merge; a CI failure afterwards is a follow-up PR. The gate's test command is `just test` (the host rung only), and the test step stays on the host
  (`test.instructions` in `.no-mistakes.yaml`): it boots no simulator and lists what only a simulator or the phone
  can show. Igor's pipeline rules (2026-10-11, `~/tmp/agent/locks/PIPELINE-RULES.md`):
  - **One pipeline run per train.** Finish the whole stack before the first push; do not push while a run is in
    flight unless its review or test step asked for that fix; never restart the no-mistakes daemon or reboot
    while runs are active.
  - **Review settles in one fix round.** Round 1 fixes every error and warning together; later rounds fix errors
    only and decide the info findings in one pass; review is capped at two rounds, the rest become issues.
  - **Live checks once, in the build turn.** The driving session runs the simulator and device checks itself,
    once per train, under the build lock, and records them in the PR body; a pipeline pass never replaces
    `just test-sim` or the phone rung.
- **Analyzer semantics** (details and evidence in `docs/analysis/`): a swing rep is top→top, about 1.2 s; the first
  swing counts too (the hike off the floor, #148): a rep over 4 s drops its walk-in or setup and counts only as a
  hike that flies to the top within 0.4 s; an upswing over 1 s is not a swing; a top over 1 s after the deepest
  hinge counts only when another hinge follows within 2.5 s (the hike does; the bell set down does not, #149);
  unmeasured joints read 0° and must not
  drive transitions; joints are chosen per frame by the confident side, not by label. Bulgarian phases run on head
  height (the front knee bends too little from a diagonal camera). Get-ups need ≥3 s up and ≥2 s down and record the
  overhead arm.
- **Video**: never transform, clip, or attach a pixel output to the `AVPlayerLayer` or its ancestors (HDR washout);
  zoom by resizing the layer frame. Trim is passthrough from the previous keyframe's *decode* time; a time-ranged
  `AVAssetReader` emits empty sync-flagged placeholder samples to ignore.
- **Audio session** stays `.ambient` + `.mixWithOthers`: the app never interrupts music.
- **Device tooling**: builds need the sandbox off and `-allowProvisioningUpdates -allowProvisioningDeviceRegistration`,
  never `-sdk` (breaks the watch target). "No provider was found" is noise. A locked phone fails launch, not install.
  `just build-device` runs xcodebuild through bug-kit's signing guard (bug-kit #53): a provisioning build while the
  Mac's screen is locked makes Xcode discard the Apple ID, so the guard waits for the unlock and exits 78 on "No
  Accounts"; then stop and tell the driver, never retry. Run the recipe whole under `~/tmp/agent/locks/build.lock`
  and `xcode-signing.lock`.
  Install the watch app separately when the watch target changed ([DEBUGGING.md](docs/DEBUGGING.md)); the watch
  takes an install only awake on the wrist: tunnel errors 1011/4000, a "usage assertion" failure or a timeout mean
  it is asleep, not that the build is bad. Say so in the handoff instead of retrying.
- **Edit files with the Read, Edit and Write tools.** Not with Python or sed scripts wrapped in a shell command,
  and not with code that reads a file into a string and assembles a patch (a JavaScript loop over Status lines,
  a `*** Begin Patch` built in `exec_command`): Igor reads the diffs, and a tool edit shows exactly what changed.
  Shell is for building, testing, git and device commands.
- **Background agents** that investigate are read-only, in a worktree, notes under `~/tmp/agent/notes/`; confirm scope
  before an agent that writes to the repo. Reap background commands when done.
- **An outside agent that writes (Codex, Muse) works in a Herdr worktree**: `herdr worktree create --cwd <repo>
  --branch <name> --base main`, the agent started in that worktree's pane (never `cd`'d into it), commits on its
  branch, never pushes; review every commit, then `git merge --ff-only <name>` and remove the worktree
  ([decision](docs/architecture/2026-09-26-agent-worktrees.md)). A fresh worktree has no `.mlpackage` (gitignored):
  `just model` for the pose model, and copy the untracked bench detector `ExerciseAnalyzer/yoloe-26s-bench.mlpackage`
  from the main checkout before building; never commit either.
- **Gym-first UI**: few large targets, HUD on the video, Recents point at Photos. Propose with a numeric plan or a
  trade-off table, then one "do it".
