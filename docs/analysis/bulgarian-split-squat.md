# Bulgarian split squat

Code: `ExerciseCore/Sources/ExerciseCore/BulgarianSplitSquatAnalyzer.swift`.

## Phases

STANDING → DESCENDING → BOTTOM → ASCENDING → STANDING (rep complete), driven by **head height relative to the
standing height, scaled by leg length**. The front knee often bends only modestly in a split squat (and reads even
less from a diagonal camera), so it scores quality but does not gate the phases.

- **Front leg**: the foot that sits lower on screen (the rear foot is up on the bench). Elevation is voted over
  recent frames (`elevationVoteFraction` 0.12 of leg length, `elevatedRecentlyFraction` 0.3).
- **Descend** when the head drops more than `descendFraction` (0.08) of leg length below standing height; **rise**
  after it comes back up `riseFraction` (0.02) from the bottom; **standing** again within `returnFraction` (0.05) of
  the standing height. Frames with spine over `maxValidSpineAngle` (60°) are rejected.

## Fixtures

| Fixture | Reps | Verified | Why |
|---|---|---|---|
| bulgarian-10reps | 8 | no | head drops 8 times at a steady ~4.2 s rhythm; the earlier front-knee analyzer counted 10 |
| bulgarian-phone | 8 | no | Igor's gym set (report 2026-09-12): 8 head drops at ~4 s, setup crouches at both ends |
| tracks/bulgarian-split-squat-20260909-98B26725 | archived | | must still analyze (`ArchivedTracks`) |

Reports: `TuningReports.testBulgarianPhoneSetUnderThresholds`, `testBulgarianTenRepSetTrace`,
`testBulgarianPhoneSignals` (knee angles, spine, ear and ankle heights per quarter second, plus a naive dip count).

## Experiments

- **2026-09-12, bulgarian-phone**: `testBulgarianPhoneSignals` showed the front knee dipping only to 110–130° from
  the diagonal camera while the head dropped by a steady fraction of leg length 8 times; phases moved from the
  front knee to head height (commit 681f98d and the AGENTS.md rule).
- Both counts are analyzer baselines. Next: Igor confirms 8 on one of them and it becomes `humanVerified`.
