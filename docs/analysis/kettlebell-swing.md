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

Reports: `TuningReports.testSwingRepTraces`, `SwingThresholdSweep.testSwingThresholdSweep`.

## Experiments

- **2026-09-12, swing-pickup-10reps (#4)**: an upswing that takes over a second is the lifter standing up from the
  bell, not a swing; `releaseMaxDuration` = 1.0 s. Reps over 4 s (walk-in, setup) discarded; unmeasured frames
  excluded from transitions (commits 6b74a93, 4344155).
- **2026-09-12, swing-lowcam-10reps (#16)**: arms read 80° behind the body and 45° in front from a low camera;
  `topArmMin` 40, `bottomArmMax` 75 (+15 margin). Count went 0 → 10, not yet confirmed by Igor (commit f3e7955).
- **2026-09-12, detector**: swings with many arm cycles and slightly uneven legs (walk-in, diagonal camera) fell to
  "ambiguous"; see [detector.md](detector.md) (commit 8bc27b5).
