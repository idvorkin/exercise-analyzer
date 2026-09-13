# Pose-to-exercise analysis notes

How a pose track becomes phases, reps and scores, what each signal means, what the camera does to it, and a log
of the experiments behind every rule. The code is the truth for *what* runs; these notes keep the *why* and the
evidence, so a threshold is never re-derived from scratch. One file per exercise, plus the detector.

| File | Covers |
|---|---|
| [kettlebell-swing.md](kettlebell-swing.md) | top / connect / bottom / release on spine, hip and arm angles; walk-in, pick-up and bell-park rejection |
| [pistol-squat.md](pistol-squat.md) | working leg from knee asymmetry; bottom from head height |
| [bulgarian-split-squat.md](bulgarian-split-squat.md) | phases on head height scaled by leg length; the front knee only scores |
| [turkish-get-up.md](turkish-get-up.md) | lying / rising / standing / lowering on uprightness; the 2026-09-12 staging study and the proposed stages |
| [detector.md](detector.md) | which exercise a set is, from floor time, arm cycles, knee asymmetry and foot elevation |
| [kettlebell-detector.md](kettlebell-detector.md) | seeing the bell with a second model: the YOLO-World Core ML trial on the sample clips (#18) |

## The pipeline

1. **Pose model** (`yolo26n-pose`, COCO-17 keypoints, normalized to the image) runs per frame on the phone; the
   simulator runs it on the CPU (~20 fps), `just analyze clip.mov` runs it on the Mac.
2. **`AnalysisPipeline`** picks the tracked person, feeds each pose to one exercise's analyzer, records the frame in a
   `PoseTrack`, and collects completed reps. Re-analysis (another exercise, Auto re-detect, an analyzer fix) replays
   the stored track and never touches the model.
3. **`BodySkeleton`** turns a pose into the per-frame signals below. Joints under the visibility threshold are
   *missing*; an angle with a missing joint reads **0** and must never drive a transition (AGENTS.md).
4. **An analyzer** runs a phase state machine over the signals (`PhaseStateMachine`: phase, frames in phase, rep
   count, one stored position per phase). Transitions need a condition to *hold* for a few frames; each completed
   rep carries its positions (for the gallery and phase navigation) and a `RepQuality` (0–100 score, feedback).
5. **`AnalysisVersion.current`** is stamped on every stored analysis; the app re-analyzes older sets on open and at
   launch (#19). Bump it in any commit that changes an analyzer, the detector or the skeleton math.

## Signals (`BodySkeleton`)

| Signal | Definition | Notes |
|---|---|---|
| `spineAngle` | torso lean from vertical, shoulder midpoint to hip midpoint | 0 upright; 0 when an end is missing |
| `armToVerticalAngle` | upper arm from vertical, the more raised reliable arm | 0 hanging, 90 horizontal, 180 overhead; one-hand swings read the working arm |
| `hipAngle` | knee–hip–shoulder on the more confident side | ~180 standing, ~90 deep hinge |
| `kneeAngle` / `kneeAngle(side)` | hip–knee–ankle | ~180 straight, ~90 deep squat; per-side for single-leg work |
| `uprightness` | (ankle.y − shoulder.y) ÷ (shoulder–hip + hip–knee + knee–ankle), longest fully-measured side | ~1 standing, ~0 lying across the frame, negative when the head lies lower on screen than the feet; camera-orientation independent because it is normalized by limb length |
| `overheadArmSide` / `overheadArmAngle` | the wrist highest above its own shoulder; its angle from vertical | nil when no wrist is above a shoulder |
| `earY`, `ankleY(side)`, `wristHeight` | head height, foot height, highest wrist over the shoulders | pixels; larger y is lower on screen |

**Sides are chosen per frame by confidence, not by label.** The model's left/right labels flip in side views and
when the lifter faces left; `bestSide` takes a whole side's joints at once so a near-side hip never pairs with a
far-side knee.

## What the camera does to the signals

- **Along the body** (phone at the head or feet, get-ups): 2-D hip and knee angles on the floor are noise (left and
  right disagree by 20–50°); uprightness and the support elbow angle stay usable.
- **Low and close** (swings, #16): arms behind the body read up to 85° and arms in front foreshorten to 40–55°, so
  arm thresholds are wide and the top is confirmed by the wrist-height peak instead.
- **Diagonal** (split squats): the front knee bends too little to gate phases; head height does the work.
- **Feet cut off**: guessed ankle positions read as one foot "raised" in every frame, so foot elevation only counts
  when both ankles are confident.
- **Mirrored clips** (#5): swing detection and counts must survive mirroring; tests replay fixtures flipped.

## Running experiments

- `just test` (~1 s) replays every fixture in `ExerciseCore/Tests/ExerciseCoreTests/Fixtures/` through the detector
  and the analyzers; counts are pinned in `PoseTrackFixtures.swift`, with `humanVerified` when Igor confirmed them.
- `swift test --filter TuningReports` prints, per fixture, every transition an analyzer took (its `trace` hook),
  each rep's checkpoint times and quality, and raw signals at 0.25–0.5 s steps. Add a report before changing a rule
  and read the numbers first; paste the table that decided the rule into the exercise's notes.
- `swift test --filter SwingThresholdSweep` counts the swing fixtures under alternative thresholds.
- `just analyze clip.mov [--exercise …] [--fixture …]` runs the model plus the analyzers on any clip on the Mac and
  can cut a fixture without the phone. Fixtures from the phone come from `Documents/recents/<id>/analysis.json`
  ([TESTING.md](../TESTING.md) has the steps).

## Keeping these notes

Every analyzer change adds an entry to that exercise's **Experiments** log: the date, the clip or fixture, what was
measured, what was decided, and the commit. A rule without an entry is a rule nobody can defend later.
