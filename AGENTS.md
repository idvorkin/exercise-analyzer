# Agent instructions: Exercise Analyzer

iOS app (SwiftUI + Core ML pose model) that counts and scores kettlebell swings, pistol squats, Bulgarian split
squats and Turkish get-ups. `ExerciseCore/` is the platform-free analysis package; `ExerciseAnalyzer/` is the app;
`ExerciseAnalyzerWatch/` the watch companion. Test architecture: [docs/TESTING.md](docs/TESTING.md).

## Rules

- **Test ladder**: host `just test` (~1 s) → simulator `just test-sim` (5–8 min) → phone `just run-device`. Verify on
  the cheapest rung that can see the change and say which rung you used. The simulator runs the model on the CPU
  (~20 fps); it has no camera, no HDR, no taps: drive it with `SIMCTL_CHILD_SWING_*` hooks and wait on log events.
- **Wrong rep count = fixture first.** Export the set's pose track from the phone's `Documents/recents/<id>/analysis.json`
  into `ExerciseCore/Tests/ExerciseCoreTests/Fixtures/`, make `swift test` fail, then fix. Never tune by reinstalling.
  Mark fixtures `humanVerified` only when Igor confirmed the count.
- **Instrument before theorizing.** For any phone-only symptom add a log event, deploy, `just pull-logs`, then fix
  from evidence. Never ship a second guessed fix. Session logs are JSON Lines with a `type` per event.
- **Bugs live in GitHub issues.** Shake reports → `just pull-logs` → `just file-bugs`; evidence and analysis go on the
  issue as a comment.
- **One commit per issue**, `Fixes #N` only when verified at the right rung, otherwise `#N` plus what remains.
  Never bundle fixes. Never `git add -A` (`.build/`, `Build/`, `.claude/worktrees/` must stay untracked).
- **Analyzer semantics**: a swing rep is top→top in 1.1–2.1 s (longer is the walk-in or setup, discard); an upswing
  over 1 s is not a swing; unmeasured joints read 0° and must not drive transitions; joints are chosen per frame by
  the confident side, not by label. Bulgarian phases run on head height (front knee bends too little from a diagonal
  camera). Get-ups need ≥3 s up and ≥2 s down and record the overhead arm.
- **Video**: never transform, clip, or attach a pixel output to the `AVPlayerLayer` or its ancestors (HDR washout);
  zoom by resizing the layer frame. Trim is passthrough from the previous keyframe's *decode* time; a time-ranged
  `AVAssetReader` emits empty sync-flagged placeholder samples to ignore.
- **Audio session** stays `.ambient` + `.mixWithOthers`: the app never interrupts music.
- **Device tooling**: builds need the sandbox off and `-allowProvisioningUpdates -allowProvisioningDeviceRegistration`,
  never `-sdk` (breaks the watch target). "No provider was found" is noise. A locked phone fails launch, not install.
  Mac tooling cannot read the phone's Photos library: clips reach the Mac only via Recents pose tracks or AirDrop.
- **Background agents** that investigate are read-only, in a worktree, notes under `~/tmp/agent/notes/`; confirm scope
  before an agent that writes to the repo. Reap background commands when done.
- **Gym-first UI**: few large targets, HUD on the video, Recents point at Photos. Propose with a numeric plan or a
  trade-off table, then one "do it".
