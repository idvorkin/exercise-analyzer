# Exercise detector

Code: `ExerciseCore/Sources/ExerciseCore/ExerciseDetector.swift`. Observes every frame of a set and decides which
exercise it was; Auto mode analyzes with the winner, and reopening a stored set in Auto re-detects (#17).

## What it counts

| Statistic | From | Used for |
|---|---|---|
| `lying_ratio`, `standing_ratio` | uprightness < 0.15 / > 0.85 over frames with a measured uprightness | get-up |
| `hands_overhead_ratio` | both wrists (confidence over 0.3) more than a quarter of a torso length over the shoulder line, over all frames | pull-up |
| `lunge_ratio` | feet over 0.8 leg lengths apart along the floor with the hips between 0.3 and 0.85 leg lengths up, over frames with both ankles confident | split squat |
| `lunge_low_ratio`, `lunge_frames` | the same wide-lunge observations over lowered poses only, plus their count | split squats with long standing/setup footage |
| `arm_cycles` | arm rises above 50° after being below 30° | swing |
| `p95_asymmetry`, `high_asymmetry_ratio` | |left knee − right knee| over the last 400 measured frames, 95th percentile (one bad frame cannot decide) and the share over 35° | pistol vs split squat vs swing |
| `elevated_ratio` | one ankle more than 0.2 leg lengths above the other, only when both ankles are confident (cut-off feet read as raised) | split squat |

## Decision order

1. Fewer than 30 frames: no decision.
2. **Turkish get-up**: on the floor in over 10 % of frames and standing in over 3 %.
3. **Pull-up**: both hands held over the shoulders in over 40 % of frames. After the get-up on purpose (below).
4. **Split squat**: in a lunge for over 15 % of frames, **or at least 30 wide-lunge observations comprising
   over 25 % of lowered poses**, and one foot held above the other in under half of them
   (that is the Bulgarian). Before the swing on purpose (below).
5. **Kettlebell swing**: at least 3 arm cycles with symmetric legs (p95 < 35°), or at least 10 cycles with p95 < 50°
   and under 20 % of frames over 35° (walk-ins and diagonal cameras make legs read a little uneven).
6. **Pistol squat**: p95 asymmetry over 80° with the feet level in over half the frames.
7. **Bulgarian split squat**: one foot held above the other in over half the frames with p95 over 20°.
8. Otherwise ambiguous (swing with low confidence).

Every fixture must detect as its own exercise with confidence ≥ 60 (`DetectionTests`), swing detection must survive
mirroring, and `DetectionReport.testDetectionMargins` prints how close each fixture sits to the boundaries.

## Experiments

- **2026-09-20, splitsquat-256C9B06-phone, #119**: 161 wide-lunge observations / 2316 stance frames = **6.95%**,
  but 161 / 531 lowered poses = **30.32%**. Old decision **Swing 97%**, now **Split Squat 90%**. The existing
  barbell fixture has **99.4%** wide/lowered; every swing and pistol fixture **0%**; get-ups **14.7–15.2%**.
  Bulgarians retain their elevated-foot gate, pull-ups their earlier overhead rule. Added 30-observation
  minimum guards against sparse setup guesses. Evidence: `TuningReports.testSplitSquatDetectionWithSetup`,
  `SplitSquatReportTests`, and all-fixture detection tests. Version `2026-09-20.2`.

- **2026-09-12**: swings with many arm cycles and pistols with moderate asymmetry fell to "ambiguous"; the cycle
  count and the percentile rules above replaced raw maxima (commit 8bc27b5).
- **2026-09-12**: the get-up rule (floor time plus standing) was added with the analyzer (commit 48c182f).
- **2026-09-19**: the pull-up rule (#108). `DetectionReport`: `hands_overhead_ratio` is 0.72 on pullup-phone-5reps,
  0.00 on every swing, pistol and split squat fixture, and 0.36 / 0.40 on the two get-ups (lying with the bell arm
  up, both hands are "over the shoulders" on screen). Asked first, the rule took tgu-phone-2sides for pull-ups
  at 40 %; asked after the get-up's floor rule, every fixture detects as itself. Threshold 0.4 (commit b56766b).
- **2026-09-19**: the split squat rule (#112). The barbell on the back reads as 23 arm cycles, so the fixture was a
  swing at 100 %; the rule goes before the swing's. `DetectionReport`, `lunge_ratio` with the feet over 0.8 apart:
  splitsquat-barbell-phone 0.28, every swing and the pistol 0.00, get-ups 0.04–0.05, pull-ups 0.09–0.12 (decided
  earlier by the hands), bulgarian-10reps 0.00, bulgarian-phone 0.20, which is why the rule also asks for a foot
  held up in under half the frames (0.25 here, 0.75–0.90 on the Bulgarians). Tried and rejected: counting a lunge
  from 0.6 apart, the analyzer's own width. The pistol's free leg out front then reads as a lunge in 21 % of its
  frames and pistol-6reps detected as split squats; at 0.8 it reads 0.00. Known ceiling: a static split squat
  never brings the feet together, so its rear heel is "held up" throughout and it reads as a Bulgarian.
