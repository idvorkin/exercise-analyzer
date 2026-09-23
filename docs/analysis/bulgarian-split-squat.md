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
- **Not a rep**: a dip that bottoms out less than `minDepthFraction` (0.2 L) below the standing height (a head
  wobble); any dip before the rear foot has been up `minSetUpSeconds` (2.5 s) (the foot going up to the bench
  mid-crouch). The standing height is forgotten only after `forgetTopAfter` (4 s) with no elevated reading: from
  a diagonal camera the front leg hides the rear ankle while standing tall.
- **Standing picture**: the frame of the highest head since the last rep, not the frame that tripped the descent.

## Fixtures

| Fixture | Reps | Verified | Why |
|---|---|---|---|
| bulgarian-10reps | 8 | no | head drops 8 times at a steady ~4.2 s rhythm; the earlier front-knee analyzer counted 10 |
| bulgarian-phone | 8 | no | Igor's gym set (report 2026-09-12): 8 head drops at ~4 s, setup crouches at both ends |
| bulgarian-4CF19A9A-phone | 8 | yes | Igor's gym set (2026-09-22, #132), diagonal camera: a setup crouch and a head wobble counted as reps 1 and 2 |
| tracks/bulgarian-split-squat-20260909-98B26725 | archived | | must still analyze (`ArchivedTracks`) |

Reports: `TuningReports.testBulgarianPhoneSetUnderThresholds`, `testBulgarianTenRepSetTrace`,
`testBulgarianPhoneSignals` (knee angles, spine, ear and ankle heights per quarter second, plus a naive dip count).

## Experiments

- **2026-09-12, bulgarian-phone**: `testBulgarianPhoneSignals` showed the front knee dipping only to 110–130° from
  the diagonal camera while the head dropped by a steady fraction of leg length 8 times; phases moved from the
  front knee to head height (commit 681f98d and the AGENTS.md rule).
- Both counts are analyzer baselines. Next: Igor confirms 8 on one of them and it becomes `humanVerified`.
- **2026-09-13, tracks/bulgarian-split-squat-20260909-98B26725 ([#55](https://github.com/idvorkin/exercise-analyzer/issues/55))**:
  the Bottom pill could never light — `bottom` existed only as a stored peak while the live phase went
  descending straight to ascending (the swing, the pistol and the get-up all report their pill phases live,
  and this note already listed BOTTOM as a phase). The machine now rests in `bottom` from the dip
  confirmation until the head rises a second `riseFraction` (pistol parity). Reps byte-identical pre/post on
  all three Bulgarian tracks (8/8/8); frames 31.16–31.19 read `bottom` in rep 7's dip; no `bottom` outside rep
  spans. Evidence: `BulgarianBottomPhaseTests` over the archived track. The pill's seek had always landed on
  the bottom peak; it was the live phase under the playhead that never said `bottom`.
- **2026-09-15, review of the entry above (no fixture)**: the bottom exit (`bottom.earY − 2 × riseFraction × L`,
  0.04 L above the confirmation level) sat *above* the completion line (`top + returnFraction × L`, 0.05 L
  below the top) for any dip shallower than 0.09 L, so such a rep could cross the completion line while still
  in `bottom` and never complete, taking every later rep with it. The exit is now the lower of the two, so
  ascending is always entered first. The three archived tracks still count 8/8/8 (their dips are all deeper);
  no fixture has a dip that shallow, which is a gap ([#77](https://github.com/idvorkin/exercise-analyzer/issues/77)).
  AnalysisVersion 2026-09-15.1.
- **2026-09-22, bulgarian-4CF19A9A-phone ([#132](https://github.com/idvorkin/exercise-analyzer/issues/132), [#131](https://github.com/idvorkin/exercise-analyzer/issues/131))**:
  10 counted, Igor: 8 ("rep 1 was just me setting up … rep 2 was garbage"). The eight real dips go 0.43–0.51 L
  deep; rep 2 was a 0.10 L head wobble; rep 1 was the rear foot going up to the bench mid-crouch (first read up at
  4.9 s, descent tripped at 6.4 s). Every Standing picture was the frame that tripped the descent, 0.6–2.6 s after
  the head's highest point ("the top isn't the top"). A first try gated on the share of a dip's frames with the
  rear foot up (setup 0.77, real 0.98–1.0 here) cut bulgarian-10reps to 3: from its camera real dips read the foot up
  in 10–50 % of frames, so that gate was dropped. Forgetting the standing height whenever the rear foot stopped
  reading up (the ankle hides behind the front leg at the top from a diagonal camera, 33–34 s here) measured
  dips from a lower head and cut the archived 98B26725 to 6. `TuningReports.testBulgarianSetupAndWobbleSweep`:
  depth 0.2 L with 2.5 s of setup counts 8 on all four tracks (depth 0.15–0.2 with setup ≤ 1.5 s leaves 9 here).
  `BulgarianStandingTests` holds every Standing picture at the highest head. AnalysisVersion 2026-09-22.1.
