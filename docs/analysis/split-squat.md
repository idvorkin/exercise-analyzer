# Split squat

Code: `ExerciseCore/Sources/ExerciseCore/SplitSquatAnalyzer.swift`. Asked for in #112 ("This is a split squat.
Let's add support for that"). Both feet on the floor, one ahead of the other; a static split squat and a lunge
stepped into from standing read the same. The rear foot on a bench is the
[Bulgarian](bulgarian-split-squat.md), which stays its own exercise: loosening its raised-foot rule would bring
back the setup crouches that rule was written against.

## Phases

STANDING → DESCENDING → BOTTOM → ASCENDING → STANDING (rep complete), driven by **the hips' height over the lower
foot, in leg lengths**. Measure hip midpoint to the lower ankle in pixels and hold the upright leg length
through the dip. Re-estimating a bent, occluded leg on every frame can turn a real bottom into an apparent
standing pose (#119). The gallery's Standing checkpoint still uses the most upright measured pose.

- **Not the head**, which the Bulgarian uses: with a bar on the back the plate hides the head from the side. Ear
  confidence on the fixture is 0.01 through every rep.
- **Both ankles must be confidently seen** (0.5), or there is no stance and the frame decides nothing.
- **Descend** when the hips sink `descend` (0.12) under the standing height (the highest since the last rep).
  **Bottom** is the lowest point, confirmed after a rise of `rise` (0.04) for 3 frames, and it counts only when the
  hips sank at least `minDepth` (0.25) **with the feet at least `minSplit` (0.5) leg lengths apart along the
  floor in three observations during the dip or its last 0.5 s of approach**. This keeps evidence of the rear
  foot before it leaves the frame. A squat with the feet together, or a bend to the floor, is not a rep.
  Back within `returnSlack` (0.08)
  of standing completes the rep, or abandons a dip that had no such bottom.
- **A rep also ends where the hips top out**, when that is under the standing height: they came up at least
  `minDepth` off the bottom, recovered at least 80% of their descent, and have been `rise` under that top for
  6 consecutive frames. The top becomes the standing height. The recovery requirement keeps a noisy bottom
  from splitting one lunge into two.
  This is the static split squat: the lifter stood tall (1.0) before stepping into the split and from then on only
  comes back to the split stance (about 0.9).
- An unfinished dip expires after 8 s from descent: camera setup or losing the person cannot join a later rep.
- **The front leg** is the one whose ankle is lower on screen (its foot is flat; the rear one is up on its toes,
  about 0.3 leg lengths higher). The knees only score; left and right are not named, because the model's labels
  flip in side views.
- **Standing checkpoint** retains the highest hip pose since the previous rep ended (or a non-rep dip was
  abandoned), including the ascent peak when a static split tops out. It does not use the last frame within
  the return tolerance: that frame can already be descending. This changes the gallery position, not the
  transition thresholds or count.

## Score

The Bulgarian's rules: 100, less 25 when the front knee stays over 100° (10 when over 85°), less 10 when the rear
knee stays over 110°, less 15 when the torso leans past 45°. HUD: FRONT, REAR, DEPTH (share of a 0.5 leg-length
sink), SPINE.

## Fixtures

| Fixture | Reps | Verified | Why |
|---|---|---|---|
| splitsquat-barbell-phone | 8 | no | Igor, 2026-09-19 (recents 952F2323), barbell on the back, side-on: eight dips in pairs, legs alternating, feet together between them; bottoms at 26.5, 31.8, 39.3, 45.0, 54.3, 60.0, 69.3, 75.2 s. Counted 0 as a swing and as a Bulgarian |
| splitsquat-256C9B06-phone | 10 | no | #119, IMG_4362.MOV, 102.7 s. Original video inspected: camera setup/unrack before 30 s, ten alternating lunges, rerack after 90 s. Rear leg leaves the frame. Igor confirmed exercise, not count |

Report: `TuningReports.testSplitSquatTrace`.

## Experiments

- **2026-09-20, splitsquat-256C9B06-phone, #119, [9b31923](https://github.com/idvorkin/exercise-analyzer/commit/9b31923)**: stored as **29 pistols**, Auto said Swing 97%, and the old
  Split Squat analyzer found **6**. Frame review of the original cached video found ten lunges near **32.5,
  37.3, 42.5, 48.2, 53.8, 59.7, 64.5, 72, 78, 87 s**. Holding the upright leg scale fixes false returns during
  occlusion. The last rep's visible split is **0.53–0.55** just before descent; requiring 0.6 at the lowest pose
  misses it. Three split observations at 0.5, including the last half-second of approach, retain it. Setup
  has only one observation above 0.5. First experiment: fixed scale alone joined camera setup to the first
  lunge and doubled the seventh; an 8 s timeout and 80% recovery before a lower top remove those errors.
  Final result: **10**, no reps in isolated **0–29 s / 90–103 s** segments, each selected bottom within 1 s of
  its visible lunge. Original fixture stays **8**, static and stepping synthetic sets stay **3**, all eight
  upright checkpoints retained. Evidence: `SplitSquatReportTests`, `TuningReports.testSplitSquatTrace`;
  version `2026-09-20.2`. Exact gallery bottom frames remain limited by the occluded pose estimates.

- **2026-09-20, splitsquat-barbell-phone, #118, [93c65dc](https://github.com/idvorkin/exercise-analyzer/commit/93c65dc)**: all eight Standing checkpoints failed a host regression
  before the fix: hips **0.960–0.976** leg lengths versus the full tops **0.997–1.010**. The old rule selected
  the last sample within 0.04 of standing. Keeping the peak pose changes their times from
  **23.90, 29.47, 37.17, 42.57, 52.00, 57.20, 66.87, 72.47 s** to
  **20.13, 29.37, 33.43, 42.33, 48.03, 56.53, 62.40, 72.17 s**. All eight assertions now pass; the count
  stays **8**, and both synthetic static-split and lunge cases stay **3**. Evidence:
  `SplitSquatAnalyzerTests.testPhoneStandingCheckpointsAreAtTheTop` and
  `TuningReports.testSplitSquatStandingCheckpoints`. Analysis version `2026-09-20.1` refreshes stored sets.

- **2026-09-19, splitsquat-barbell-phone** (the first analyzer). The reps sink 0.41–0.59 with the feet 0.85–1.11
  apart at the bottom; the two dips that are not reps (bending out of frame for the bar at 13 s, walking off at
  81 s) sink 0.10–0.14 with the feet 0.15–0.33 apart. `minDepth` from 0.10 to 0.40 counts 8 (0.45 counts 4);
  `minSplit` from 0 to 0.6 counts 8 (1.0 counts 3). Scores 100 except reps 4 and 8 at 90 ("Good depth, a little lower": the front knee stayed just over 85°). The
  simulator's own pose pass of the clip: split squat 88 %, 8 reps.
- **2026-09-19, the code review's static split** (no recorded set yet, so a stick figure:
  `SplitSquatAnalyzerTests`). Stand tall feet together (1.0), step into the split (0.89), three dips to 0.45 that
  come back to 0.89. The first analyzer counted **0 of 3**: ASCENDING's only exit was `height > top − 0.08` = 0.92,
  the standing height is only relearned in STANDING, and the machine sat in ASCENDING for the rest of the clip.
  With "topped out" it counts 3; lunges from standing still 3; `splitsquat-barbell-phone` still 8, every rep
  ending "standing again" (the new exit never fires on it). A real static set should replace the stick figure
  when Igor records one.
- **2026-09-19, an archived set**: `tracks/pistol-squat-20260913-96ED6CFB` (stored as 23 "pistols" in 70 s) now
  detects as split squats, 10 reps. Its track agrees: both ankles on the floor at the bottom (y 722 and 759 of
  1280), hips to 0.55, feet 1.0 apart, feet together between reps. Not a fixture: nobody has watched it.
