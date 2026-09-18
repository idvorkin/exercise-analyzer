# Kettlebell swing

Code: `ExerciseCore/Sources/ExerciseCore/KettlebellSwingAnalyzer.swift` (ported from swing-analyzer's
`KettlebellSwingFormAnalyzer.ts`).

## Phases

TOP → CONNECT → BOTTOM → RELEASE → TOP (rep complete). Each phase stores one position: the best extreme for TOP and
BOTTOM, the first qualifying frame for CONNECT and RELEASE.

| Phase | Meaning | Condition (degrees, `SwingThresholds`) |
|---|---|---|
| TOP | lockout: arms at peak height, standing tall | spine < 25 (`topSpineMax`), hip > 150 (`topHipMin`), arm > 40 (`topArmMin`); confirmed by the wrist-height peak |
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

Reports: `TuningReports.testSwingRepTraces`, `SwingThresholdSweep.testSwingThresholdSweep`, and
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
  poses and stay uncounted; the capture now logs `capture_gap` so the hole itself can be fixed from evidence. with many arm cycles and slightly uneven legs (walk-in, diagonal camera) fell to
  "ambiguous"; see [detector.md](detector.md) (commit 8bc27b5).
