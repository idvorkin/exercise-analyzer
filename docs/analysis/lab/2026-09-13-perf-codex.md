# Bell detector performance review — 2026-09-13

The short Mac comparison found **no measurable penalty from changing the detector floor/cap from 0.25/6 to 0.15/12**: three-run median 107 → 108 fps, approximately 9.35 → 9.26 ms/frame. Treat that difference as noise, not a speedup. The first current-settings run was slower; the other five runs clustered at 106–109 fps. The historical phone cost remains dominated by the detector call, 12.0 ms/frame out of about 22.9 ms/frame total. There is no new phone timing here.

The five-fixture host report, including the backward pass, took a median **0.391 seconds for 6,756 frames**. That is 0.058 ms per input frame for the entire debug report, including JSON loading, exercise analysis, tracking, and metric calculations. It does not isolate the backward pass or measure the latest tracker on the phone.

## Scope and provenance

- Read the supplied performance brief in full, AGENTS.md, the four required project documents, detector analysis notes, and the detector, sampler, tracker, pipeline, frame storage, CLI, and app offline code.
- Worktree: `/Users/idvorkin/gits/exercise-analyzer/.claude/worktrees/codex-bell`, branch `codex-bell`, HEAD `6e2b69d45b4b3b11f3f2dbacde68fba63ddcd682`.
- This checkout contains `85ed8e5`, `72439f4`, and `be9c75d`, but **not `fd97209` or `a6a2cf5`**. Those latter commits were reviewed with `git show`; no cherry-pick, checkout, or implementation was performed. Their furniture-follow veto, head veto, and nearest-wrist selection costs below are source estimates, not measured here. Detector, sampler, and CLI sources have no diff between this HEAD and `a6a2cf5`, so the detector-settings comparison still applies to those sources.
- Existing edits to `TuningReports.swift` and `docs/analysis/kettlebell-detector.md` were preserved. The report test includes the existing `inReps` metric extension. No repository source or documentation was edited for this task; no commit or push.
- Verification rungs: host and Mac model only. One heavy command at a time, release build with one job. Only the 165-frame swing video was decoded. The two-minute get-up was read as stored JSON in the required host report, never run through a model.
- Model packages are absent from the worktree. The runs read the packages in `/Users/idvorkin/gits/exercise-analyzer/ExerciseAnalyzer/`, using existing compiled caches. Pose manifest timestamp: `1784865044`; bell: `1789281384`. The Mac reports `arm64`; CPU marketing name was not collected.
- SHA-256 of each package's `Data/com.apple.CoreML/model.mlmodel` (graph files, not full-package hashes): pose `6282a18cac05d8c3eaa6e15a8de6c165d899c14630bf35e049aac72ff88c2743`; bell `f8a45f5ab79aea773a42226839639786976b2181a790f1e145ba06eab8527960`.

## Measurements and timing boundaries

| Work / setting | ms per input frame | Basis |
|---|---:|---|
| Phone pose, historical IMG_4342 | 10.7 | Previously measured, `docs/analysis/kettlebell-detector.md`; SDK `result.inferenceMs` |
| Phone detector call, historical | 12.0 | Previously measured; includes Vision preprocessing/model execution, parsing, suppression, color sampling, and per-call pool draining |
| Phone decode/bookkeeping window, historical | 0.35 | Previously measured; window includes loop-tail work as well as next-sample decoding |
| Phone extraction total, historical | ≈22.9 | Derived from reported 43.7 fps; 3,989 frames in 91.3 s, footprint reported flat at 73 MB |
| Mac extraction, old detector settings 0.25/6 | ≈9.35 | Derived from measured median 107 fps, three runs |
| Mac extraction, current detector settings 0.15/12 | ≈9.26 | Derived from measured median 108 fps, three runs |
| Mac settings difference, current minus old | ≈−0.09 | Derived, within run-to-run variation; no resolved regression |
| Mac full five-fixture report, including both tracker directions | ≈0.058 | Derived from measured median 391 ms / 6,756 frames; debug build, includes loading and reporting |
| Backward tracking alone / newest head gates | Not isolated | Backward work is contained in the preceding report; newest gates absent from this checkout |
| Detector Vision request, dense parse, NMS, color individually | Not isolated | Contained in the 12.0 ms historical phone detector call; need Instruments or stage timers to split |

Phone component figures are rounded and have different measurement boundaries; do not force them to sum exactly or add the Mac report time to the phone total. The 12 ms number is **not pure neural-network inference** despite the log field's name.

The app's extraction loop is now `ExerciseAnalyzer/OfflineAnalyzer.swift:60`; `VideoPoseSession.swift:578` logs `offline_pass` before invoking exercise analysis. `analyzeExtracted` at line 630 subsequently runs the pipeline, fills rep images, and logs every analyzed frame. Thus neither that `offline_pass` fps nor `posetrack` fps includes forward/backward tracking, image filling, or saving. The CLI stops its extraction clock at `Sources/posetrack/main.swift:220` and calls the pipeline at line 257. The CLI uses its own pose Vision path; it is not the app's SDK pose predictor.

### Six short-video runs

Built the missing release executable with `swift build -c release --product posetrack --jobs 1` in `ExerciseCore` (9.27 s). Default compute units `.all`, BGRA 1920×1080 frames, color sampling enabled, no trace or fixture output. No explicit warmup run was excluded. Runs were serial and interleaved in the order shown.

| Order | Settings | Printed seconds | Printed fps | Process wall seconds | Maximum RSS bytes |
|---:|---|---:|---:|---:|---:|
| 1 | Current, run 1 | 2.0 | 84 | 2.39 | 128,204,800 |
| 2 | Old, run 1 | 1.6 | 106 | 1.70 | 99,680,256 |
| 3 | Current, run 2 | 1.5 | 109 | 1.65 | 105,578,496 |
| 4 | Old, run 2 | 1.5 | 107 | 1.68 | 108,691,456 |
| 5 | Current, run 3 | 1.5 | 108 | 1.66 | 106,414,080 |
| 6 | Old, run 3 | 1.5 | 108 | 1.67 | 107,495,424 |
| | **Current median** | **1.5** | **108** | **1.66** | **106,414,080** |
| | **Old median** | **1.5** | **107** | **1.68** | **107,495,424** |

Raw stdout and `/usr/bin/time -l` results: `/tmp/bell-lab/perf-current-{1,2,3}.log` and `/tmp/bell-lab/perf-old-{1,2,3}.log`. The printed fps is rounded to an integer; reciprocal milliseconds above are approximate. Maximum RSS medians are 101.48 MiB current and 102.52 MiB old. Short process RSS is not the iPhone's physical footprint and does not establish long-clip memory stability. The first-run slowdown is consistent with warmup/cache effects, but its cause was not profiled.

Reproduction from the worktree root:

```sh
ExerciseCore/.build/release/posetrack \
  /Users/idvorkin/tmp/agent/swing-samples/swing-sample-4reps.mp4 \
  --model /Users/idvorkin/gits/exercise-analyzer/ExerciseAnalyzer/yolo26n-pose.mlpackage \
  --exercise kettlebell-swing \
  --bell-model /Users/idvorkin/gits/exercise-analyzer/ExerciseAnalyzer/yoloe-26n-kettlebell.mlpackage
```

For old settings, prefix `POSETRACK_BELL_MAX=6` and append `--bell-conf 0.25`. Both settings use the **same current-worktree tracker**, not a historical tracker. Every model run counted four reps. Printed detector seen/held-at-hand was 98%/100% current versus 92%/98% old. These proximity metrics are not visual ground truth, particularly because the two later false-positive fixes are absent here.

### Host report

`/usr/bin/time -l swift test --filter TuningReports/testBellTrackerHeldPerFixture`, in `ExerciseCore`: test-body times **0.437, 0.383, 0.391 s**, median **0.391 s**; process walls **2.43, 0.86, 0.81 s**, median **0.86 s**. All three runs passed with identical report values. This is a reporting test, not an assertion of tracking accuracy.

| Fixture | Frames | Stored sightings | Mean sightings/frame | Held, printed | Held inside reps |
|---|---:|---:|---:|---:|---|
| swing-4reps | 165 | 852 | 5.16 | 100% | 126/126 |
| swing-1h-9reps | 594 | 6,083 | 10.24 | 98% | 317/328 |
| tgu-phone-2min | 3,989 | 5,166 | 1.30 | 82% | 1,492/1,633 |
| pistol-6reps | 914 | 2,152 | 2.35 | 4% | 44/502 |
| bulgarian-10reps | 1,094 | 2,987 | 2.73 | 0% | 0/502 |
| Total | **6,756** | **17,240** | **2.55** | | |

These files have 202 completely empty sighting frames in total. Filtering their stored sightings to confidence ≥0.25 and a six-box prefix leaves 645 / 3,558 / 3,473 / 1,260 / 846 sightings respectively. That is a cheap **stored-output estimate**, not a new detector run or a count of raw dense anchors. It shows why the one-hand rack is the important cap stress case: approximately 10.24 versus 5.99 color calls/frame. This short-video timing alone does not cover that crowded-rack cost.

## Where time and memory go; what changed tonight

1. **Per-frame model work stays the same.** `BellDetector.detect`, lines 69–94, allocates a new `VNCoreMLRequest`, a handler, and a one-request array each call. It creates observation/tensor and shape arrays with `compactMap`/`map`. `.scaleFit` preprocessing and the same full model execute once per frame at either confidence/cap setting. The dense output is 37×8,400 elements and the unused mask prototype is 32×160×160: 1,130,000 elements, about 2.16 MiB Float16 or 4.31 MiB Float32 of logical output payload per frame, before allocator/framework overhead. Lowering the floor does not reduce or increase those tensor dimensions. The model and `VNCoreMLModel` are already loaded once, not reloaded per frame.

2. **Dense parsing scans 8,400 anchors even at the old floor.** `parseDense`, lines 116–139, reads one score per anchor for the bundled single class through a dtype-specific closure. Let P be the number passing the floor: it then reads another 4P coordinates, performs two letterbox point conversions per candidate, and appends valid boxes to a growing array without reserved capacity. It does not read all 37 channels per anchor; mask coefficients are ignored. Lowering 0.25→0.15 increases P, coordinate work, and array growth, not the 8,400 score reads. Actual P was not instrumented.

3. **Suppression processes boxes it later discards.** `suppressOverlaps`, lines 99–110, allocates a sorted candidate array and a growing kept array. It sorts P boxes, then checks each against previously kept boxes using rectangle intersection/IoU: O(P log P + P×K), worst-case quadratic if K grows with P. The cap is applied only afterward with `prefix(maxSightings)`. Therefore 6→12 does not itself change NMS work; lowering the floor can. A pathological 8,400 mutually disjoint candidate set would require 35,275,800 pair comparisons, though normal bell outputs are nowhere demonstrated to approach this.

4. **Color sampling is CPU byte reading, not Core Image.** `BellColorSampler.swift:14` locks/unlocks the same CVPixelBuffer separately for every retained box, queries its geometry/stride, averages central-region BGRA bytes, and allocates a three-Float array. It does not copy the full frame. Up to six extra boxes mean up to six additional lock/unlock pairs, sample loops, and color arrays. The comment claiming at most 32×32 samples is wrong: `step = max(1, extent / 32)` floors the division; a 63-pixel extent uses stride 1. Each axis can sample 63 points, so the real maximum is **3,969 pixels/box**, **47,628 at cap 12**, versus **23,814 at cap 6**. Typical counts depend on box size. This is bounded work, with three byte reads per sampled pixel, not a scan of an entire 1080p frame.

5. **Tracking does small loops and many small temporary collections.** `Bell.swift:88–225`: `staticZones` creates a mapped key array and a Set per frame plus an aggregate dictionary. Each tracker step uses `updateResting` with up to S×previous-S distance checks (36→144 worst-case when both frame caps double), new `next`/`still` arrays, a filtered static/resting list, wrist points, follow candidates, and start candidate/distance arrays. Array `contains` on sightings invokes structural equality, potentially including RGB arrays. Start distance, follow confidence, flat-box comparisons, velocity coasting, and lost-state counters add cheap arithmetic; longer loss tolerance is constant-size state, not a frame history. Tracking newly visits 202 empty frames in these fixtures, resetting/aging/coasting as intended.

6. **Backward fill adds one more full tracker traversal and O(F) temporary storage.** `filledBackward`, lines 103–112, tracks all F frames in reverse (6,756 additional calls here), builds a growing `[BellSighting?]`, and uses `zip(...).map` to allocate a replacement `[FrameRecord]`. `reversed()` is a view, not another full-array copy. Frame values share nested pose, sighting and RGB array buffers via Swift copy-on-write; they do not deep-copy pixels. `PoseTrack.replaceAll` then calls `sorted` on the already chronologically ordered result, adding array/sort work (general sort worst case O(F log F); ordered input may be faster). All this happens after the extraction fps clock stops. The full debug report is already only 391 ms, so do not spend days optimizing it before measuring phone CPU samples.

7. **Later gates, source-reviewed only.** `fd97209` changes follow rejection from the resting list to the combined resting/static-zone list; no new model work or new full-track pass. `a6a2cf5` constructs up to five visible head points per tracker step and can test five rectangle containments per candidate for each start/follow filter (up to 60 per filter at S=12). Its follow winner is nearest a wrist when wrists exist, not merely a tie-break on equal last-position distance. A `.min` over 12 candidates makes 11 comparisons, up to 22 temporary wrist-distance arrays and 44 distance evaluations with two wrists, per tracker direction. Short-circuit filters usually reduce this. These costs warrant a single-pass selection loop if profiling highlights them, not removal of the vetoes.

8. **Retained memory is frame metadata, not decoded video.** Every frame keeps up to 12 sightings with RGB arrays, versus six before. Nominal field payload of a sighting is roughly 44 bytes (CGRect, confidence, Array reference), before alignment and heap headers; 23,934 additional sightings at six extra across 3,989 frames imply roughly 1 MiB of struct payload plus color buffers/headers. The real increase is clip-dependent, and this get-up fixture averages only 1.30 sightings. Frames, analysis results, and backward buffers add O(F) metadata. Preserve the detector's inner autorelease pool and the app's outer per-frame pool: prior phone failures came from retained CI frames and autoreleased Vision tensors. One 1920×1080 BGRA frame alone is 7.91 MiB before row padding. The Mac CLI lacks the app's outer frame pool, another reason not to extrapolate its short-run RSS to the phone.

## Ranked optimization proposals

Ranking favors simple changes preserving outputs. **Phone savings below are low-confidence planning estimates, not measured stage timings or promises.** Zero is included because these costs may disappear into the noise. Do not add the ranges together; mechanisms overlap. Instruments should decide whether any small CPU proposal is worth implementing.

| Rank | Proposal and mechanism | Expected phone saving / budget | Risk to held %, controls, and code touched |
|---:|---|---|---|
| **1** | **Batch color reads under one pixel-buffer lock.** Query base address, width, height, and row stride once; average all retained boxes using the exact existing lattice and accumulation order. | Likely sub-ms; planning **0–0.2 ms/frame**, removing up to 11 redundant lock/unlock pairs. Benefit scales with rack sightings; no whole-frame-copy saving is claimed. | Low: identical RGB means identical color gates and weight votes. Preserve format checks, bounds and unlock lifetime. `BellDetector.detect`, `BellColorSampler.averageColor`. Compare raw RGB and tracked boxes. |
| **2** | **Reuse one configured VNCoreMLRequest per detector instance.** Keep `.scaleFit` on the persistent request; keep a handler tied to each input image and keep autorelease pools. | Likely sub-ms; planning **0–0.3 ms/frame** of request/setup/allocation work. Model execution and tensors remain. | Low–medium: verify exclusive serial ownership, fresh results after failed requests, and whether persistent results retain one tensor set or more. This is a proposal, not a demonstrated API speedup. `BellDetector` init/detect. Exact output comparison plus long phone footprint trace. |
| **3** | **Stop greedy NMS after accepting `maxSightings` boxes.** Preserve the same full confidence sort and tie order, stop after the 12th accepted box, reserve kept capacity. | Likely sub-ms; planning **0–0.3 ms/frame** on ordinary outputs, potentially more on clutter. **Zero early-stop benefit on frames with fewer than 12 surviving boxes.** Raw P/K counts decide. | Low: later candidates cannot change the already accepted prefix in this greedy algorithm. Do not truncate raw candidates to 12 before NMS; duplicates would crowd out real bells. `BellDetector.suppressOverlaps` and its caller. Assert identical retained ordered boxes for empty/dense/tied/overlap cases. |
| 4 | Specialize the dense-score loop by dtype outside the anchor loop; avoid per-element closure dispatch, reserve candidate storage; vectorize only the score threshold step if a profile justifies it. | Planning **0–0.3 ms/frame**; 8,400 scores is a small scan. First inspect optimized code because the compiler may already remove overhead. | Low–medium: preserve arbitrary strides, Float16/Float32 handling, inclusive floor, anchor order and coordinates. `parseDense`, `reader`, `BellDetectorParseTests`. A dtype mistake previously crashed the phone. |
| 5 | Reduce tracker temporary arrays and reverse-fill storage; cache candidate wrist distance, retain stable min selection, fill an output buffer in reverse, avoid sorting a known-ordered replacement. | Expected small: planning **under 0.1 ms/input-frame on phone**, uncalibrated. Memory benefit clearer: remove backward optional array and redundant sorting storage. Entire measured Mac debug report averages 0.058 ms/frame. | Low–medium: output equality across five fixtures and BellTests; preserve tie order, reset/coasting semantics and one reverse state update per frame. `Bell.swift`, `AnalysisPipeline`, `PoseTrack`; give ordered replacement an explicit invariant rather than weakening generic sorting. |
| 6 | Enforce a true ≤32×32 color lattice using ceiling stride, or reduce samples further. | Planning **0–0.2 ms/frame**. Worst box's 3,969 reads become at most 1,024, but memory access/locking may dominate. | Medium: changes RGB, hue-veto decisions and weight votes near boundaries; reducing color quality can increase control false holds. `BellColorSampler`. Keep separate from rank 1 so rank 1 can preserve behavior exactly. |
| 7 | Skip detector inference on some frames, retaining full pose rate; try every second frame, or a separate bell pass limited to padded rep spans. | Larger conditional estimate: **every second frame saves up to ~6 ms/input-frame** at historical 12 ms/call, ≈23.9 s/3,989 frames and ~59 fps before overhead. A span covering 57% of frames saves ≈5.16 ms/frame, ~20.6 s, minus second decode/setup. | High: tracker needs fresh sightings for starts, color identity, reverse fill and furniture statistics. Existing three-frame coasting does not guarantee correctness under deliberate skips. Rest counts currently reset on empty detections, and zone share counts all frames; sparse sampling must explicitly preserve time/observed-frame semantics. Rep-span mode needs a two-pass flow or stored poses; do not retain all pixels. `OfflineAnalyzer.extract`, `VideoPoseSession`, `BellTracker`, fixture format if marking skipped frames. Evaluate exact boxes/false holds, in-rep coverage and controls; no two-minute model trial was run here. |
| 8 | Export the same detector without the unused segmentation branch while preserving its dense detection head and fixed outputs. | Unknown; bounded by the detector's 12 ms/call. Logical output payload could fall from 1,130,000 to 42,000 elements (37-channel dense output plus prototype → five-channel dense boxes/scores), saving ~2.08 MiB/frame at Float16; payload reduction is not a latency measurement. | Medium–high: graph change may alter outputs or placement; do not switch to the inferior one-to-one head or dynamic NMS. `scripts/model-trials/export_bell_detector.py`, model package, output parser validation. Trial on the Mac first, compare dense scores/boxes and controls, then phone timing. |

Avoid reverting the 0.15 floor, 12-box cap, head veto, or backward fill just for speed. The settings comparison found no resolved short-clip cost; those changes address known detection/identity failures. The current proximity percentage can reward a head or rack false positive, so preserving or increasing that number alone is not validation.

## Handoff for Claude's Instruments run

On the phone, separate `Vision perform`, dense parse, suppression, color, and pool drain, then time static-zone setup, forward analysis, backward fill, replacement sorting, and the later image/log/save work. Record P (floor survivors), K (NMS survivors), actual color-box/sample counts, and empty detector frames. Keep `offline_progress` memory and a long-pass check because this short Mac benchmark cannot reproduce iOS retention bugs. `decode_ms` starts its next interval before frame append/progress/heartbeat, so it includes that loop-tail work; use a narrower timer if optimizing decoding.

The first three proposals are ready for profiling decisions, not implementation. No optimization was implemented, and no phone, simulator, issue, or external message action was taken.
