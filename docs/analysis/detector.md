# Exercise detector

Code: `ExerciseCore/Sources/ExerciseCore/ExerciseDetector.swift`. Observes every frame of a set and decides which
exercise it was; Auto mode analyzes with the winner, and reopening a stored set in Auto re-detects (#17).

## What it counts

| Statistic | From | Used for |
|---|---|---|
| `lying_ratio`, `standing_ratio` | uprightness < 0.15 / > 0.85 over frames with a measured uprightness | get-up |
| `hands_overhead_ratio` | both wrists (confidence over 0.3) more than a quarter of a torso length over the shoulder line, over all frames | pull-up |
| `arm_cycles` | arm rises above 50° after being below 30° | swing |
| `p95_asymmetry`, `high_asymmetry_ratio` | |left knee − right knee| over the last 400 measured frames, 95th percentile (one bad frame cannot decide) and the share over 35° | pistol vs split squat vs swing |
| `elevated_ratio` | one ankle more than 0.2 leg lengths above the other, only when both ankles are confident (cut-off feet read as raised) | split squat |

## Decision order

1. Fewer than 30 frames: no decision.
2. **Turkish get-up**: on the floor in over 10 % of frames and standing in over 3 %.
3. **Pull-up**: both hands held over the shoulders in over 40 % of frames. After the get-up on purpose (below).
4. **Kettlebell swing**: at least 3 arm cycles with symmetric legs (p95 < 35°), or at least 10 cycles with p95 < 50°
   and under 20 % of frames over 35° (walk-ins and diagonal cameras make legs read a little uneven).
5. **Pistol squat**: p95 asymmetry over 80° with the feet level in over half the frames.
6. **Bulgarian split squat**: one foot held above the other in over half the frames with p95 over 20°.
7. Otherwise ambiguous (swing with low confidence).

Every fixture must detect as its own exercise with confidence ≥ 60 (`DetectionTests`), swing detection must survive
mirroring, and `DetectionReport.testDetectionMargins` prints how close each fixture sits to the boundaries.

## Experiments

- **2026-09-12**: swings with many arm cycles and pistols with moderate asymmetry fell to "ambiguous"; the cycle
  count and the percentile rules above replaced raw maxima (commit 8bc27b5).
- **2026-09-12**: the get-up rule (floor time plus standing) was added with the analyzer (commit 48c182f).
- **2026-09-19**: the pull-up rule (#108). `DetectionReport`: `hands_overhead_ratio` is 0.72 on pullup-phone-5reps,
  0.00 on every swing, pistol and split squat fixture, and 0.36 / 0.40 on the two get-ups (lying with the bell arm
  up, both hands are "over the shoulders" on screen). Asked first, the rule took tgu-phone-2sides for pull-ups
  at 40 %; asked after the get-up's floor rule, every fixture detects as itself. Threshold 0.4 (commit b56766b).
