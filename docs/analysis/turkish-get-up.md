# Turkish get-up

Code: `ExerciseCore/Sources/ExerciseCore/TurkishGetUpAnalyzer.swift`. One rep is lying → standing → lying with the
bell pressed overhead the whole way.

## Phases and stages

Counting runs on a coarse machine over **uprightness** (median of the last 15 frames, each condition held for
`holdFrames` = 8, about a quarter second): LYING → RISING → STANDING → LOWERING → LYING (rep complete).

| Threshold | Value | Meaning |
|---|---|---|
| `lyingMax` | 0.15 | at or below this the body is on the floor |
| `risingMin` | 0.30 | above this the get-up has started |
| `standingMin` | 0.85 | standing |
| `loweringMax` | 0.70 | a standing athlete is on the way down |
| `minRiseSeconds` / `minLowerSeconds` | 3 s / 2 s | anything faster is a pose glitch, not a get-up (#14) |
| `armDriftWarn` / `armDriftBad` | 15° / 25° | overhead arm from vertical, 90th percentile over the rep |

Inside RISING and LOWERING a **stage tracker** names the step (since 2026-09-12, the study below). It only moves
forward within a direction and never touches the count; the stage is the phase a frame reports and the gallery
keeps. The support arm is the one opposite the rep's majority overhead arm; an unmeasured elbow reads 0 and never
drives a stage.

| Stage | Enter when | Position stored | Threshold |
|---|---|---|---|
| Elbow | raw uprightness above `lyingMax` with the support elbow bent, even before the coarse machine calls it rising (the step can be over in half a second) | first such frame | `elbowBentMax` 140° |
| Hand | support elbow straight, held 8 frames | first frame | `handElbowMin` 150° |
| Kneel | uprightness in [`kneelMin`, `kneelMax`] for `kneelHoldSeconds` | middle of the plateau | 0.25–0.45, 1 s |
| Lunge | uprightness above `lungeMin` for `lungeHoldSeconds` after the kneel (the bridge pokes above it for under a second) | first frame of the hold | 0.45, 1 s |
| Standing | `standingMin` (coarse) | tallest frame | |
| Lunge ↓ | `loweringMax` (coarse) | first frame | |
| Kneel ↓ | uprightness at or below `kneelMax` for `kneelHoldSeconds` | middle of the plateau | |
| Elbow ↓ | support elbow bent with uprightness at or below `kneelMax`, held 8 frames | first frame | |
| Lying | `lyingMax` after ≥ 2 s down (coarse) | last lying frame before the elbow step | |

A stage that was never entered (a fast rep, an unmeasured elbow) gets the frame nearest its typical uprightness
between the neighbouring stages that were, so every rep carries all nine positions. Gallery order: Lying, Elbow,
Hand, Kneel, Lunge, Standing, ↓ Lunge, ↓ Kneel, ↓ Elbow; the HUD shows six pills and a down stage lights the
same pill as its up stage. Quality: arm drift, a rushed descent (down < 0.6 × up), and which arm held the bell
(majority of `overheadArmSide` over the rep) so a set reads as one rep per side.

## Fixtures

| Fixture | Reps | Verified | Why |
|---|---|---|---|
| tgu-phone-2min (IMG_4342) | 2 | no | Igor's first clip: two get-ups, one per side, rest lying between (reps 23–54 s and 91–116 s) |
| tgu-phone-2sides (IMG_4343) | 2 | yes | #14: a pose glitch at 14 s stood the athlete up and down inside a second and counted as rep 1 |
| tracks/turkish-get-up-20260912-* | archived | | must still analyze |

Reports: `TuningReports.testTurkishGetUpTrace` (transitions, stages and quality), `testTurkishGetUpSignals` (the
half-second signal table below). Tests: `GetUpStageTests` pins every stage of the four reps to the landmark windows
below (±0.5 s) and every rep to all nine positions in order.

## Experiments

### 2026-09-12: sub-second "get-ups" (#14)

IMG_4343 at 14.5 s: uprightness jumped 0.96 → lying and back within 0.4 s (a pose glitch while lying) and counted a
rep. A get-up now needs 3 s up and 2 s down; discarding a partial rep no longer resets the count. Commit 56eaeb8.

### 2026-09-12: staging study (Igor: "the get-up is going to need more stages")

`testTurkishGetUpSignals` on both fixtures, four reps. The two clips are shot differently: tgu-phone-2sides is
along the body (lying reads −0.8 to −0.98, head at the bottom of the frame), tgu-phone-2min from the side (lying
reads 0.0). Uprightness bands agree across both because it is normalized by limb length; 2-D hip and knee angles on
the floor do not (left and right differ by 20–50° from the along-body camera).

Rep 1 of tgu-phone-2sides, one row per half second (`up` uprightness, `supElb` the support arm's elbow angle,
`hipL/kneeL` the left side):

```
   t  phase      up  supElb  hipL kneeL   what it is
23.0  lying    0.28    56    66    49    roll to the elbow starts
24.5  rising   0.08    81   131   112    on the elbow
25.0  rising   0.41   107    82    78    elbow straightening
25.5  rising   0.34   146    72    52    on the hand (tall sit)
27.5  rising   0.71   163   157   127    bridge / leg sweep (brief)
29.0  rising   0.34   157    94    96    knee down, hand on the floor
31.5  rising   0.34   161    86    60    … held for 3 s
32.0  rising   0.60   175    76    54    hand off the floor, half-kneeling lunge
34.0  rising   0.49   167    97    74    …
34.5  rising   0.87   145   133   121    standing up
39.5  standing 1.00   150   176   180    tall
45.5  standing 0.65    14   149   118    lunge on the way down
48.0  lowering 0.27   163    91    38    knee down
53.0  lowering 0.02     0    68   170    lying
53.5  lying    0.37   106   146   131    (elbow bent again: the lowering's last step)
```

Landmarks across the four reps (times in seconds; L/R is the overhead arm):

| Landmark | 2sides rep 1 (L) | 2sides rep 2 (R) | 2min rep 1 (L) | 2min rep 2 (R) |
|---|---|---|---|---|
| leaves lying (up > 0.15) | 23.0 | 97.5 | 22.5 | 91.0 |
| **Elbow**: support elbow bent | 24.5–25.0 (81–107°) | 96.5–97.5 (86–104°) | 23.5–24.5 (71–111°) | 91.5–92.0 (128–135°) |
| **Hand**: support elbow straight ≥ 150° | 25.5 (146°) | 98.0 (175°) | 25.0 (174°) | 93.0 (179°) |
| bridge / sweep (up 0.5–0.7, hip > 150°) | 27.5–28.5 (hip 157–161°) | 99.5–100.0 (163°) | 26.5–27.0 (174°) | not measurable (hip 39–44°) |
| **Kneel**: plateau at up 0.25–0.45 | 29.0–31.5 (0.29–0.34) | 100.5–102.5 (0.31–0.34) | 28.0–30.5 (0.29–0.46) | 95.5–96.5 (0.35–0.40) |
| **Lunge**: up 0.45–0.80 after the plateau | 32.0–34.0 (0.40–0.68) | 103.0–104.5 (0.41–0.58) | 31.0–34.0 (0.66–0.74) | 97.0–99.0 (0.46–0.56) |
| **Stand**: up ≥ 0.85 | 34.5 | 105.5 | 35.0 | 100.0 |
| lowering starts (up < 0.7) | 45.5 | 115.0 | 46.5 | 110.0 |
| Kneel ↓ plateau | 50.5–51.5 (0.27–0.32) | 117.0–118.0 (0.33) | 49.0–50.0 (0.28–0.56) | 111.5–113.0 (0.36–0.44) |
| Elbow ↓: support elbow bent again | 53.5 (106°) | (outside the window) | 54.0 (94°) | 115.5–116.0 (79–81°) |
| lying (up ≤ 0.15) | 53.1 | ~121 | 54.5 | 116.0 |

What the numbers say:

- **Uprightness carries five of the six stages.** Elbow and Hand sit at 0.1–0.45, the kneel is a flat plateau at
  0.25–0.45 lasting 2–3 s in all four reps, the lunge is 0.45–0.80, standing ≥ 0.85. Elbow versus Hand is not an
  uprightness difference; it is the **support elbow angle** (bent 70–135° on the elbow, straight ≥ 146° on the
  hand), which was clean in all four reps.
- **The bridge / sweep is not worth a stage yet.** It lasts about a second and its signal is the hip angle, which the
  along-body camera does not measure reliably (one rep reads 39–44° where the others read 157–174°).
- **The lunge band overlaps the kneel band at its bottom** (rep 1 reads 0.40 in the lunge). Order fixes that: the
  lunge is whatever follows the kneel plateau and holds above 0.45.
- **The down side mirrors the up side** with the same bands, but Hand ↓ is not separable from Kneel ↓ without a
  reliable hand-on-floor signal (the wrist-below-hip test is camera dependent), so the way down gets Lunge ↓,
  Kneel ↓, Elbow ↓ only.

### 2026-09-12: stages built

Implemented as above. First run put three of the four reps in the windows; 2sides rep 2 took the one-second bridge
bump (0.62 / 0.50 at 99.5–100.0 s) as the lunge, so the lunge now has to hold above 0.45 for a second like the
kneel, after which its kneel midpoint moved to 101.5 s and its lunge to 104.5 s. The same rep's elbow step
(97.5 s, 86°) fell under the median-filtered lying threshold, so the elbow candidate is judged on the raw
uprightness. Stored positions after the change (seconds):

| Rep | Lying | Elbow | Hand | Kneel | Lunge | Standing | ↓ Lunge | ↓ Kneel | ↓ Elbow |
|---|---|---|---|---|---|---|---|---|---|
| 2sides 1 (L) | 24.0 | 24.0 | 25.9 | 31.0 | 32.9 | 41.6 | 45.8 | 49.7 | 52.3 |
| 2sides 2 (R) | 97.5 | 97.5 | 98.3 | 101.5 | 104.5 | 111.2 | 115.5 | 118.9 | 120.2 |
| 2min 1 (L) | 22.9 | 22.9 | 25.0 | 29.6 | 31.0 | 40.1 | 46.7 | 53.1 | 53.3 |
| 2min 2 (R) | 90.9 | 91.2 | 92.8 | 96.3 | 97.2 | 106.0 | 110.2 | 113.6 | 114.9 |

Lying and Elbow share a frame when the elbow step starts on the last floor frame. ↓ Kneel of 2min rep 1 never
held the band (uprightness jittered 0.28–0.56 on the way down, see the table above), so it is a filled frame
between ↓ Lunge and ↓ Elbow; the count and the other stages are unaffected.
