# Pistol squat

Code: `ExerciseCore/Sources/ExerciseCore/PistolSquatAnalyzer.swift` (ported from swing-analyzer's
`PistolSquatFormAnalyzer.ts`).

## Phases

STANDING → DESCENDING → BOTTOM → ASCENDING → STANDING (rep complete).

- **Working leg**: the more bent knee (knee asymmetry), re-evaluated per rep so a set can alternate legs.
- **Bottom**: the lowest head position (`earY`), confirmed once the head has risen again for a few frames.
- **Descending / ascending checkpoints**: the frames nearest 50 % of the head travel on the way down and up.

| Threshold | Value | Meaning |
|---|---|---|
| `standingKneeMin` | 150° | working knee nearly straight |
| `standingSpineMax` | 25° | relatively upright |
| `descendingKneeThreshold` | 140° | descent starts when the working knee drops below this |
| `ascendingKneeThreshold` | 90° | ascent starts when the working knee rises back above this |
| `maxValidSpineAngle` | 60° | frames where the person is basically horizontal are rejected |

## Fixtures

| Fixture | Reps | Verified |
|---|---|---|
| pistol-6reps | 6 | no (analyzer baseline) |

## Experiments

- **2026-09-12, detector**: pistols with moderate asymmetry fell to "ambiguous"; the detector now takes the 95th
  percentile of knee asymmetry over 80° with the feet level as a pistol (commit 8bc27b5).
- No human-verified pistol set yet. Next: one phone set, `just pull-logs`, cut a fixture, have Igor confirm the count.
