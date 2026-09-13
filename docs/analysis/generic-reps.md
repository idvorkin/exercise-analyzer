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

Pending the host run (`swift test --filter TuningReports.testGenericRepCounter`); paste the table here.

| Fixture | Known | Generic | Signal | Period | r | Conf | Detector conf | Hit (±1) |
|---|---|---|---|---|---|---|---|---|
| swing-4reps | 4 | | | | | | | |
| swing-1h-9reps | 9 | | | | | | | |
| swing-phone-13reps | 13 | | | | | | | |
| swing-pickup-10reps | 9 | | | | | | | |
| swing-walkin-9reps | 9 | | | | | | | |
| swing-lowcam-10reps | 10 | | | | | | | |
| pistol-6reps | 6 | | | | | | | |
| bulgarian-10reps | 8 | | | | | | | |
| bulgarian-phone | 8 | | | | | | | |
| tgu-phone-2min | 2 | | | | | | | |
| tgu-phone-2sides | 2 | | | | | | | |

Expected misses: both get-up fixtures — a get-up takes 20–30 s per rep, far above the 6 s band, so the counter
should report 0 (or a weak partial rhythm) there. If the other three exercises' fixtures land within ±1, that
is the bar met: three of four.
