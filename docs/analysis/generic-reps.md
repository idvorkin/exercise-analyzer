# Generic reps: counting from repetition alone

Code: `ExerciseCore/Sources/ExerciseCore/GenericRepCounter.swift`. Igor, by voice (#71): "If we can't detect
the exercise, let's just look for reps from repetition of weight and skeleton."

When Auto mode cannot name the exercise with confidence, there is still usually something moving up and down
at a steady rhythm. This counter finds that rhythm without knowing the exercise: no angles, no thresholds in
degrees, just periodicity in a few height signals.

## Method

1. **Candidate signals**, per frame, in units of the person's height (the median limb-measured body length over
   the set, so camera distance divides out; larger = higher on screen):
   - `head`: ears midpoint, else nose;
   - `hips`: midpoint of the visible hips;
   - `wrists`: mean of the reliable (conf > 0.3) wrists;
   - `bell`: the tracked bell's center, only when a bell is held.
   A signal with fewer than 10 measured samples, or spanning under 1 s, does not run.
2. **Resample** each signal onto its own uniform grid (linear interpolation; phone frames jitter) and smooth
   with a ±0.15 s moving average.
3. **Pick the signal** with the strongest periodicity: the max autocorrelation (Pearson over the overlap, so
   long lags are not penalized) at a lag between 0.5 s and 6 s. Faster is jitter, slower is the walk-in, the
   setup and the rest. Below `minPeriodicity` 0.4, or a signal flatter than `minRange` 0.08 person-heights,
   nothing is periodic enough and the count is 0.
4. **Count peak-to-peak cycles**: local maxima clearing the median by `hysteresisFraction` (0.25) of the
   signal's p95–p5 range, consecutive peaks kept only when the trough between them dips the same fraction
   below the median, cycles outside 0.5–6 s rejected. The count is the number of peak-to-peak intervals, so a
   set whose track starts and ends exactly on peaks reads one under; the ±1 bar below absorbs that.
5. **Confidence** 0–100 = 100 × periodicity × (0.4 + 0.6 × coverage), where coverage is the share of the track
   span inside counted cycles: a strong rhythm through most of the set scores near 100.

Report: `TuningReports.testGenericRepCounter`. The number that decides: how many fixtures land within ±1 of
the known count. Bar for wiring it as the fallback: ±1 on at least three of the four exercises' fixtures.

## Results

Host run 2026-09-13 (`just test` green, `swift test --filter TuningReports.testGenericRepCounter`; raw output in
`/tmp/bell-lab/generic-reps-table.txt`). Rep intervals printed by the report are omitted here except where noted.

| Fixture | Known | Generic | Signal | Period | r | Conf | Detector conf | Hit (±1) |
|---|---|---|---|---|---|---|---|---|
| swing-4reps | 4 | 0 | head | 5.4 s | 1.00 | 40 | 88 | no |
| swing-1h-9reps | 9 | 0 | hips | 0.5 s | 0.64 | 25 | 91 | no |
| swing-phone-13reps | 13 | 0 | wrists | 1.5 s | 0.83 | 33 | 100 | no |
| swing-pickup-10reps | 9 | 0 | hips | 0.5 s | 0.77 | 31 | 97 | no |
| swing-walkin-9reps | 9 | 0 | hips | 0.5 s | 0.51 | 21 | 97 | no |
| swing-lowcam-10reps | 10 | 10 | wrists | 1.5 s | 0.51 | 40 | 92 | **yes** |
| pistol-6reps | 6 | 0 | wrists | 0.5 s | 0.79 | 32 | 78 | no |
| bulgarian-10reps | 8 | 1 | head | 4.3 s | 0.85 | 40 | 95 | no |
| bulgarian-phone | 8 | 7 | wrists | 0.5 s | 0.67 | 54 | 90 | **yes** |
| tgu-phone-2min | 2 | 0 | head | 0.5 s | 0.98 | 39 | 100 | no |
| tgu-phone-2sides | 2 | 0 | head | 0.5 s | 0.98 | 39 | 100 | no |

Archived tracks (no known count; drift watch only): the three 20260912 swing tracks at wrists/1.5 s read 10/10/10
(66FAD1F2, 71AD553F, 9F8F947D — byte-identical numbers to swing-lowcam-10reps, likely the same set under
three ids), 394148D3 reads 5, FBAFBE8D,
A62F3AC2, DAA72AB3, EFE59129 read 0; archived bulgarian reads 7 like bulgarian-phone; all three archived get-ups
read 0. Same failure modes as the fixtures, no new ones.

## Verdict: not wired

2 of 11 fixtures within ±1, on 2 of 4 exercises (swing via lowcam, Bulgarian via phone). The bar was ±1 on at
least three exercises' fixtures, so per the brief the counter stops here: no `ExerciseKind.unknown`, no story
002 change, no `AnalysisVersion` bump. `GenericRepCounter` stays as the experiment harness behind
`TuningReports.testGenericRepCounter`.

## Why it failed

- **The period picker locks onto the band edges.** Seven rows report period exactly 0.5 s — the bottom of the
  search band, i.e. the argmax sitting on the edge, which means no interior autocorrelation peak at all. A slow
  drift is trivially self-similar at the shortest lag (both get-ups: r 0.98–0.99 at 0.5 s, saved from counting
  only by the range gate), and short-lag noise outscores the true rhythm (pistol wrists r 0.79 at 0.5 s).
- **Raw autocorrelation prefers the slowest trend, not the reps.** swing-4reps picks head at 5.4 s with r 1.00:
  the walk-in/setup drift correlates perfectly with itself while the 1.2 s swings ride on top of it. Nothing
  detrends before the autocorrelation.
- **The right signal and period still count 0.** swing-phone-13reps finds wrists at 1.5 s with r 0.83 — the rep
  rhythm — but the global median ± 0.25 × range gate keeps every peak-to-peak cycle out. One rep depth that
  differs (first hike, last rep, setup) vetoes the whole set, because the hysteresis is one global band instead
  of per-cycle prominence.
- **The two hits are fragile.** bulgarian-phone counts 7/8 off a 0.5 s period — the wrong rhythm giving almost
  the right count, since its intervals sit ~3.5–4 s apart for reasons the period does not explain. lowcam's 10/10
  ends with a 25.9–29.5 s interval: 3.6 s spanning the bell park, a junk cycle the duration band let through.

## What a next attempt should change

1. **A period band per signal from the exercise's known cadences** — or at minimum, reject an argmax sitting on
   the band edge and detrend (subtract a slow moving average) before the autocorrelation, so drift cannot
   outscore reps and edge locks read as "not periodic".
2. **Pick the signal by the count's plausibility, not raw autocorrelation** — e.g. count cycles under each
   candidate period first and prefer the signal whose cycles cover the track at a steady cadence, rather than
   handing the win to the highest r.
3. **Hysteresis relative to the smoothed local range** — per-cycle prominence (each peak against its neighbouring
   troughs) instead of one global median ± fraction gate, so uneven rep depths don't veto the set.
4. Keep the get-ups out of scope until the band extends past 6 s: 20–30 s reps need a minutes-long track and a
   different (rise-and-lie, not peak-to-peak) cycle definition.
