# Performance: how the offline pass is measured, and what it costs today

The question "how much did this change cost?" is answered on three rungs, cheapest first, and never by feel.
The numbers below are from 2026-09-12/13 (the bell detector work, #18); the method is the part to keep.
Raw material: [lab/2026-09-13-perf-brief.md](lab/2026-09-13-perf-brief.md) (the brief Codex worked from),
[lab/2026-09-13-perf-codex.md](lab/2026-09-13-perf-codex.md) (its ranked findings), and the "Performance" and
"H22" sections of [lab/2026-09-12-bell-lab-notebook.md](lab/2026-09-12-bell-lab-notebook.md).

## The method

1. **Say what you expect before measuring.** Pure Swift per frame (the tracker, the gates, the backward pass) is
   microseconds and will not show; a second model pass, a lower detector floor or a bigger box cap might. Write
   the expectation down, then measure; a surprise either way is the finding.
2. **Mac A/B with posetrack, three runs each, one clip.** `just analyze <clip>` with the old settings passed as
   flags (`--bell-conf 0.25`, `POSETRACK_BELL_MAX=6`) against the defaults, wall time and fps from the summary
   line. One heavy process at a time; the one-hand clip (594 frames) is the right length. Detector off is the
   floor to compare against.
3. **`sample` the process** (`sample posetrack 15`) when a number moves: the top of the stack says whether the
   time is ours (Swift symbols) or the platform's (Neural Engine waits, vImage conversions, BNNS). Nothing of
   ours has appeared yet; the levers so far were all in how the models are driven.
4. **The phone, by the instrumented run** (story 037: start-panel row or `SWING_DEBUG_RUN=1`, then
   `just pull-logs`): every stored set through both models, `offline_pass` per set with fps, per-model
   milliseconds, thermal state, low power, battery and memory footprint, `debug_run` with the mean fps. The same
   eight sets minutes apart is the A/B. Only this rung sees the Neural Engine on the phone, thermal throttling
   and memory; the Mac predicts direction, not magnitude.
5. **Ask a second model to rank the code** with the brief in `lab/2026-09-13-perf-brief.md` as the template:
   what changed, where the per-frame time could go, what to measure cheaply, rank by expected ms per frame, name
   the risk of each. Sub-millisecond items are recorded and not shipped.

## What it found (2026-09-12/13)

| Change | Expected | Mac (posetrack) | Phone (instrumented run) |
|---|---|---|---|
| tracker gates, coasting, backward pass, head/wrist rules | invisible | invisible (0.39 s for 6,756 frames of replay) | invisible |
| detector floor 0.25→0.15, cap 6→12 | small, more colour samples | 49–50 → 48 fps on the one-hand clip (~3 %) | 43.7 → 61 fps on the get-up (a warm engine and a shorter set; no cost measurable) |
| detector on at all | halves the pass | 98 → 48 fps | 12 ms a frame at 43.7 fps before tonight |
| **detector on a second thread while the pose model runs** (3ba7902) | 48 → 55–65 if the engine pipelines | **58–61 → 83–85 fps** (+40 %) | **38.6 → 77.1 fps** mean over eight sets, pose 9–12 ms and detector 11–15 ms overlapping, 52 MB, thermal nominal |

`sample` on the Mac: kernel waits (the Neural Engine), then `vConvert_ARGB8888toPlanarF` in vImage (each model's
planar float input from the 1080p frame, twice a frame), then BNNS. Nothing from Swift. Codex's ranked list, all
sub-millisecond and not shipped: batch the colour reads under one buffer lock, reuse one `VNCoreMLRequest`, stop
NMS after the cap, specialise the dense-score loop. Its one large lever, the detector every second frame (up to
6 ms a frame), was not taken: starts, colour votes and furniture statistics all read every frame.

The pass with the detector now runs at nearly the detector-off speed; the night's tracker work cost nothing
measurable and the concurrency doubled the phone's throughput.

## When to run it again

Any change to `OfflineAnalyzer.extract`, `BellDetector` (floor, cap, input size, a new package),
`BellColorSampler`, or a new model in the pass: Mac A/B first, then the instrumented run on the phone with the
same stored sets, both numbers into the experiment entry of the analysis note that motivated the change.
