# Pull-up

Code: `ExerciseCore/Sources/ExerciseCore/PullUpAnalyzer.swift`. Asked for in #108 ("This is a pull up. Add support").

## Phases

HANG → PULLING → TOP → LOWERING → HANG (rep complete), driven by **how far the shoulders sit under the bar, in
torso lengths** (`under`; negative when the shoulders are over the bar line). The hands do not move, so the bar is a
fixed line and the body's travel is the whole signal. A rep is hang to hang and counts when the body is back down.

- **The bar line** is the mean wrist height, learned only from frames where both wrists are over the shoulders and
  well seen (confidence ≥ `barWristConfidence` 0.7), smoothed, and held through the top. At the top the head and
  the arms hide the wrists: their confidence falls to 0.5 and the model guesses them down at the elbows, 0.2–0.36
  torso lengths under the real bar. Per-frame wrists would shorten every rep.
- **Torso length** (shoulder midpoint to hip midpoint) is learned in the hang and frozen during a rep.
- **Taking the bar**: both wrists at least `gripAboveShoulders` (0.25) over the shoulders. **Letting go**: every
  wrist seen sits more than `letGoUnderBar` (0.7) under the bar line for 3 frames, or no wrist is seen for 30.
  Hands by the sides read 1.0 under it.
- **The hang** is the lowest the shoulders have been since the bar was taken or the last rep ended. **Pulling**
  starts `startRise` (0.25) over it. **The top** is the highest point, confirmed once the shoulders have sunk
  `topConfirmDrop` (0.1) for 3 frames, and it counts only if the rise was at least `minRise` (0.6). Back within
  `returnSlack` (0.15) of the hang completes the rep; the same return without a top abandons the pull (feet
  finding the rack's pegs, a shuffle on the bar). Letting go after a real top completes the rep too.
- **Elbows only score.** From behind they fold onto the upper arm and read 5–95° at the top; in the hang they read
  165–171° / 155–162°.

## Score

100, less 20 when the shoulders stop more than `chinOverBar` (0.2) under the bar line (the chin is about 0.2 torso
lengths over the shoulder line), less 40 past `halfRep` (0.45), less 15 when the elbows never reached
`straightElbow` (150°) in the rep. HUD: PULL (share of the hang-to-bar distance covered) and ELBOW.

## Fixtures

| Fixture | Reps | Verified | Why |
|---|---|---|---|
| pullup-phone-5reps | 5 | no | Igor, 2026-09-19 (recents 3678371A), from behind, feet on the rack's pegs: 14 s of setup with the hands on the bar, tops at 17.3, 21.6, 26.1, 30.4, 34.9 s, then the climb down. The phone counted 0 as a Bulgarian split squat |
| pullup-sim-5reps | 5 | no | the same clip through the simulator's CPU pose pass; its wrists wander further at the top |

Report: `TuningReports.testPullUpTrace` (every transition with `under`, the reps, and the count under other
`minRise` and `letGoUnderBar` values).

The set #108 was reported on (recents 2A48F5E6) cannot be a fixture: its 38 s recording was trimmed to the 9 s
around the one "split squat" the wrong analyzer found, and the pull-ups were cut away with the rest.

## Experiments

- **2026-09-19, pullup-phone-5reps** (the first analyzer). Signals every 0.27 s: wrists steady at y 300–320 px of
  1280 from 1.3 to 42.4 s; shoulders 363–377 during the setup on the pegs (`under` 0.48–0.74), 404–417 in the hang
  (0.86–0.97), 276–283 at the five tops (−0.28 to −0.31): a rise of 1.21–1.28 per rep against 0.2 for the setup.
  `minRise` sweep: 0.2 and 0.3 count 6 (the setup), 0.45 to 1.1 count 5, 1.3 counts 0; 0.6 sits in the middle of
  the plateau. The climb down (39.7 s) starts a pull and ends off the bar without a top.
- **2026-09-19, pullup-sim-5reps**: the same clip in the simulator counted 3. The first grip rule kept the hands
  "on the bar" while the wrists were within 0.35 torso lengths of the line; at the tops of reps 3 and 5 the hidden
  left wrist was guessed at 340–344 px against a line of 308 (0.32–0.36 under), the grip read as lost and the rep
  was dropped. Replaced by the let-go rule above (far under the line, for 3 frames); `letGoUnderBar` from 0.2 to
  1.2 counts 5 on both tracks, because the other wrist stays near the line. Both fixtures 5 (commit b56766b, with
  the analyzer).
