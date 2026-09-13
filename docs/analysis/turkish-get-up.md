# Turkish get-up

Code: `ExerciseCore/Sources/ExerciseCore/TurkishGetUpAnalyzer.swift`. One rep is lying → standing → lying with the
bell pressed overhead the whole way.

## Phases today

LYING → RISING → STANDING → LOWERING → LYING (rep complete), on **uprightness** alone (median of the last 15 frames,
each condition held for `holdFrames` = 8, about a quarter second).

| Threshold | Value | Meaning |
|---|---|---|
| `lyingMax` | 0.15 | at or below this the body is on the floor |
| `risingMin` | 0.30 | above this the get-up has started |
| `standingMin` | 0.85 | standing |
| `loweringMax` | 0.70 | a standing athlete is on the way down |
| `minRiseSeconds` / `minLowerSeconds` | 3 s / 2 s | anything faster is a pose glitch, not a get-up (#14) |
| `armDriftWarn` / `armDriftBad` | 15° / 25° | overhead arm from vertical, 90th percentile over the rep |

Positions stored per rep: the last lying frame, the frame nearest halfway upright on the way up ("Up"), the tallest
standing frame, the frame nearest halfway upright on the way down ("Down"). Quality: arm drift, a rushed descent
(down < 0.6 × up), and which arm held the bell (majority of `overheadArmSide` over the rep) so a set reads as one
rep per side.

## Fixtures

| Fixture | Reps | Verified | Why |
|---|---|---|---|
| tgu-phone-2min (IMG_4342) | 2 | no | Igor's first clip: two get-ups, one per side, rest lying between (reps 23–54 s and 91–116 s) |
| tgu-phone-2sides (IMG_4343) | 2 | yes | #14: a pose glitch at 14 s stood the athlete up and down inside a second and counted as rep 1 |
| tracks/turkish-get-up-20260912-* | archived | | must still analyze |

Reports: `TuningReports.testTurkishGetUpTrace` (transitions and quality), `testTurkishGetUpSignals` (the half-second
signal table below).

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

### Proposed stages (not built)

Lying → **Elbow** → **Hand** → **Kneel** → **Lunge** → Standing → **Lunge ↓** → **Kneel ↓** → **Elbow ↓** → Lying.

| Stage | Enter when (held 8 frames) | Position stored |
|---|---|---|
| Elbow | up > 0.15 and support elbow < 140° | first frame |
| Hand | support elbow ≥ 150° | first frame |
| Kneel | up in 0.25–0.45 for ≥ 1 s after Hand | midpoint of the plateau |
| Lunge | up > 0.45 after Kneel | first frame |
| Standing | up ≥ 0.85 (unchanged) | tallest frame (unchanged) |
| Lunge ↓ | up < 0.70 (unchanged `loweringMax`) | first frame |
| Kneel ↓ | up < 0.45 for ≥ 1 s | midpoint |
| Elbow ↓ | support elbow < 140° with up < 0.45 | first frame |
| Lying | up ≤ 0.15 after ≥ 2 s down (unchanged) | last lying frame (unchanged) |

Design: the four-state counter (lying / rising / standing / lowering, with the 3 s and 2 s guards) stays exactly as
it is and keeps owning the rep count; a **stage tracker** runs inside rising and lowering, advances only forward
within a direction, and reports the fine stage as the frame's `phase`. The support elbow is taken on the side
opposite the rep's majority overhead arm (the per-frame overhead label flips), and an unmeasured elbow (0°) never
drives a transition. Gallery order grows from 4 to 10 columns; the HUD keeps six pills (Lying, Elbow, Hand, Kneel,
Lunge, Standing) with the down stages lighting the same pill. Verified on the host first: both fixtures must still
count 2, every rep must carry all ten positions at the times in the landmark table (±0.5 s), then the phone.
