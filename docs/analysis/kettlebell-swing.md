# Kettlebell swing

Code: `ExerciseCore/Sources/ExerciseCore/KettlebellSwingAnalyzer.swift` (ported from swing-analyzer's
`KettlebellSwingFormAnalyzer.ts`).

## Phases

TOP → CONNECT → BOTTOM → RELEASE → TOP (rep complete). Each phase stores one position: the best extreme for TOP and
BOTTOM, the first qualifying frame for CONNECT and RELEASE.

| Phase | Meaning | Condition (degrees, `SwingThresholds`) |
|---|---|---|
| TOP | lockout: arms at peak height, standing tall | spine < 25 (`topSpineMax`), hip > 160 (`topHipMin`), arm > 40 (`topArmMin`), or > 32 within 0.4 s of the release (`ballisticTopArmMin`, `ballisticReleaseMax`), or, within that same 0.4 s, > 20 with the wrists no more than 0.4 torso lengths below the shoulders (`wristTopArmMin`, `wristTopRiseMin`, #139); confirmed by the wrist-height peak |
| CONNECT | arms vertical against the body before the hinge | arm < 25 (`connectArmMax`), spine < 25 (`connectSpineMax`) |
| BOTTOM | deepest hinge, arms behind the body | arm < 75 + 15 (`bottomArmMax`, anything short of horizontal), spine > 35 (`bottomSpineMin`), hip < 140 (`bottomHipMax`) |
| RELEASE | arms leaving the body after the hip snap | arm < 25 (`releaseArmMax`), spine < 25 (`releaseSpineMax`) |

## Rules that reject non-swings

- **An upswing over 1 s is not a swing** (`releaseMaxDuration`, #4). The upswing is ballistic: the arms reach the
  top 0.15–0.3 s after crossing vertical. Standing up after parking the bell, or after picking it up, looks like a
  release but the arms rise seconds later, if at all.
- **A rep longer than 4 s is discarded** (`maxRepDuration`, #15). Top to top takes about 1.2 s, a slow first hike
  about 2 s; longer "reps" are the walk-in or the pick-up flowing into the first swing.
- **Unmeasured frames do not drive transitions** (0° joints are skipped); reps longer than 4 s were once produced by
  such frames.
- **A hole in the track ends the rep in progress** (`maxFrameGap` 0.5 s, #94). Half a second is a whole bottom, so
  the phases either side of a hole are not one swing. Nothing is counted again until the lifter is seen at a real
  top (upright, hips open, arms raised); the hole costs the swings inside it and no more.
- **Arm thresholds are wide on purpose** (#16): a low, close camera reads arms behind the body at up to 85° and arms
  in front at 40–55°; the spine and hip conditions separate top from bottom, so the arm only has to exclude
  hanging arms.
- **A low top counts only on a fast upswing** (`ballisticTopArmMin` 32 within `ballisticReleaseMax` 0.4 s, #97).
  One-arm swings with the upper arm on the ribs peak at 37–49°; a lifter who parked the bell and stands up with
  the arms a little forward reads 33–37° too, but gets there 0.57–0.9 s after the arms cross vertical, a swing in
  0.10–0.27 s.
- **The top is a lockout** (`topHipMin` 160, #97): real tops read hip ≥ 171°; standing up from the bell park and
  walking off reads 151–156°.

## Quality

Scored per rep from the stored positions (lockout angles, hinge depth); mirrored clips must score the same
(`RepCountTests.testSwingCountsMatchWhenMirrored`).

## Fixtures

| Fixture | Reps | Verified | Why it exists |
|---|---|---|---|
| swing-4reps | 4 | yes | baseline |
| swing-1h-9reps | 9 | yes | one-hand swing: the working arm is the raised one |
| swing-phone-13reps | 13 | yes | phone recording |
| swing-pickup-10reps | 9 | yes | #4: the bend to pick the bell up (first second) and the park at the end once counted |
| swing-walkin-9reps | 9 | yes | #15 (IMG_4337): the walk-in and pick-up (0.5–6.6 s) counted as rep 1 |
| swing-lowcam-10reps | 10 | no | #16 (IMG_4340): low, close camera; counted 0 before the arm thresholds were relaxed |
| swing-hole-7reps | 7 | no | #94: a live set whose recording lost 12.68–14.88 s; 9 swings, 2 cut by the hole |
| swing-onearm-10reps | 8 | no | #97: ten one-arm swings with the upper arm on the ribs, arm peaks 37–49° at the top; counted 5. The first two are not countable yet (see Experiments); the bell park at the end must not be a rep |
| swing-farcam-10reps | 10 | no (Muse) | #139 (9283D45A): far camera behind the lifter, arms foreshortened, the float reads 30–38°; counted 1 |
| swing-farcam-5tops | 4 | no (Muse) | #140 (CDC08BF2): same camera; the auto-trim (#141) cut the clip on the fifth top; counted 1 |

Reports: `TuningReports.testSwingTopArmSweep` (every swing fixture's and archived swing track's count per
`ballisticTopArmMin`; `SWING_TOP_HIP`, `SWING_BALLISTIC`, `SWING_MAX_REP` rerun it under other thresholds),
`TuningReports.testSwingWristRiseSweep` (the same rows per `wristTopRiseMin`, off first; `SWING_WRIST_ARM`
overrides `wristTopArmMin`), `TuningReports.testSwingRepTraces`, `SwingThresholdSweep.testSwingThresholdSweep`, and
`TuningReports.testSwingSignals` (every frame's angles and phase for one archived track, `SWING_TRACK=<name>
SWING_FROM=12 SWING_TO=17`).

## Experiments

- **2026-09-12, swing-pickup-10reps (#4)**: an upswing that takes over a second is the lifter standing up from the
  bell, not a swing; `releaseMaxDuration` = 1.0 s. Reps over 4 s (walk-in, setup) discarded; unmeasured frames
  excluded from transitions (commits 6b74a93, 4344155).
- **2026-09-12, swing-lowcam-10reps (#16)**: arms read 80° behind the body and 45° in front from a low camera;
  `topArmMin` 40, `bottomArmMax` 75 (+15 margin). Count went 0 → 10, not yet confirmed by Igor (commit f3e7955).
- **2026-09-18, swing-hole-7reps (#94)**: a 22 s live set counted 6; tops at 4.97, 6.5, 8.0, 9.5, 11.0, 12.5,
  [14.0], 15.55, 17.1, 18.65 make 9 swings. The track has no frames from 12.68 to 14.88 s (the main thread hung
  2.65 s, the queued frames held the camera's buffers and the capture stopped delivering: 599 frames delivered,
  586 analyzed, in the recording as well as live). After the hole the machine was still in TOP from 12.5 s, took
  the upswing at 15.14 for CONNECT, and finished that rep at 16.81: 4.6 s from its top, discarded by
  `maxRepDuration`. With `maxFrameGap` the rep in progress is dropped at the hole and the next one starts at the
  top at 15.54: 6 → 7, spans 1.10–1.43 s, the other swing fixtures unchanged. The two swings in the hole have no
  poses and stay uncounted; the capture now logs `capture_gap` so the hole itself can be fixed from evidence
  (commit 7beca0c).
- **2026-09-12, detector**: swings with many arm cycles and slightly uneven legs (walk-in, diagonal camera) fell to
  "ambiguous"; see [detector.md](detector.md) (commit 8bc27b5).
- **2026-09-18, swing-onearm-10reps (#97)**: a 24 s one-arm set counted 5; the video has ten tops (5.1, 6.6, 8.1,
  9.7, 11.3, 12.8, 14.3, 15.9, 17.5, 19.1 s), bell at chest to head height. The upper arm stays on the ribs and the
  forearm lifts the bell, so shoulder→elbow peaks at only 37–49° at the top, and on both sides alike: the model
  puts the working wrist on the guard hand, so the two arms read the same. With `topArmMin` 40 the tops at 11.3 and
  19.1 (peaks 39° and 37°) never left RELEASE, and the machine then ran one phase late (the hinge labelled TOP,
  the real top labelled CONNECT), merging two swings into one 2.3 s rep. Lowering `topArmMin` alone
  (40/38/36/34/32/30/28: this set 5/7/9/9/9/9/9, the seven other fixtures unchanged) looked clean on the
  fixtures and was not: over the 28 archived swing tracks, 32 added a false last rep to three sets (F853A918
  10 → 11, 96FEBD60 9 → 10, FD1FCA37 17 → 18) and one to this set. All four are Igor parking the bell, standing
  up and walking to the phone with the arms a little forward, 33–37°, which overlaps the real tops (37–49°). Two
  things tell them apart. Speed: a real upswing passes the cut-off 0.10–0.27 s after RELEASE, the three parks
  0.57–0.9 s after, so the low cut-off applies only to a ballistic upswing (`ballisticTopArmMin` 32 within
  `ballisticReleaseMax` 0.4 s; `topArmMin` stays 40). `testSwingTopArmSweep`, window 0.3/0.4/0.5/0.6 s at 32°:
  this set 8/8/8/8, 73014BDE 6/8/8/8 (two real swings, 1.55 s rhythm), F853A918 10/10/10/11; at 28° F853A918 is
  11 at every window. Hip: this set's park stands up fast (0.14 s) but with hip 151–156°, real tops read ≥ 171°;
  `SWING_TOP_HIP` 150/160/166: this set 9/8/8, nothing else moves up to 166 (at 170 swing-lowcam loses a rep).
  `topHipMin` 150 → 160. Result: this set 5 → 8 (spans 1.17–1.47 s), 73014BDE 6 → 8, the other 7 fixtures and
  26 tracks unchanged. Also rejected: `maxRepDuration` 3 s (removes the parks, costs a first rep in eight sets).
  The two swings still missing: the first comes off the floor after 4.7 s of setup and is dropped by
  `maxRepDuration`, as in swing-pickup-10reps; the second goes with it, because standing up with the bell reads
  as CONNECT and the first top (5.1 s) is never a TOP, so no rep starts there. Rejected: abandoning a rep whose
  BOTTOM lasts over 1–2.5 s (removes the park, but swing-pickup 9 → 8 at every value and swing-lowcam 10 → 8–9:
  a held hike is a long bottom too); CONNECT → TOP when the pose is a top (recovers the second swing, 9 real
  reps, but swing-lowcam 10 → 3 and swing-pickup 9 → 10: foreshortened arms bounce across the cut-off). A
  shoulder→wrist angle would separate a top from hanging arms better, but the wrist here is mislabelled, so it
  was not tried. Not yet confirmed by Igor.
- **2026-09-26, swing-farcam-10reps / swing-farcam-5tops (#139, #140)**: two sets from the 09-25 session counted
  1 each. Frames show real swings (bell at chest height, arms straight out); Muse counts 10 and 5 tops (the second
  clip was cut by the auto-trim, #141). The camera is far (the lifter fills 22 % of the frame height) and behind
  him to one side, so the arms point away from it: standing-tall arm p90 33–34° against 41–47° for the sets of the
  same session that counted 9–10. The wrist, though, rises to 15–30 px below the shoulders in both. Lowering
  `ballisticTopArmMin` does not fix it (`testSwingTopArmSweep`: 30° gives 4 and 2, 28° gives 6 and 2, and
  F853A918 gains its park at both). New measure `BodySkeleton.wristRise`: wrist height over the torso length,
  scale-free (about -1 hanging, near 0 at chest height). First as an extra top rule at any speed
  (`testSwingWristRiseSweep`, arm > 20°, rise ≥ -0.7/-0.6/-0.5/-0.4/-0.3): the target sets recover (9283D45A
  1 → 10 at -0.7…-0.4, 8 at -0.3) but eight other tracks gain a rep at -0.5, among them the three known parks
  (F853A918, 96FEBD60, FD1FCA37). Limited to a ballistic upswing (within `ballisticReleaseMax`, like the #97
  rule), -0.4 moves nothing but the three far-camera sets: 9283D45A 1 → 10, CDC08BF2 1 → 4, 3BEF7CEF 0 → 2
  (a 9 s trimmed fragment starting mid-set, 4 tops by Muse); at -0.5 F853A918's park and two 09-16 sets
  (73014BDE, B69762F7) gain one. `wristTopRiseMin` -0.4, `wristTopArmMin` 20. Not yet confirmed by Igor.
