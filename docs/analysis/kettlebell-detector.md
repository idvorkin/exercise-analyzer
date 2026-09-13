# Kettlebell detector (#18)

Can a second model see the bell? Tried on the Mac with Core ML (rung 1.5, `scripts/model-trials/`) on 2026-09-12.

## How the models relate

- The pose model (`yolo26n-pose`, 3 MB) knows one class, person, and its 17 keypoints. It cannot report a bell, and
  there is no off-the-shelf model that does pose and a kettlebell class at once: a bell needs a **second model, a
  second Core ML run per frame** on the same pixel buffer.
- COCO detectors have no kettlebell class. An **open-vocabulary detector** does: YOLO-World takes class names as
  text, and Ultralytics bakes the text embeddings in at export, so the Core ML model has a single class
  "kettlebell" and no text encoder at runtime.
- Cost per frame on the phone: the pose model runs in about 10 ms on the Neural Engine (`offline_pass`
  `avg_infer_ms`, 94 fps on a 48 s clip); the detector is the same size class, so expect the offline pass to go from
  ~94 fps to ~50 fps with both, and live analysis at 30 fps to stay comfortable. Memory: one more model in RAM.

## Trial: YOLO-World v2 (small), class "kettlebell", Core ML, 640 px

`scripts/model-trials/export_bell_detector.py world` exports `yolov8s-worldv2.mlpackage` (23 MB, fp16, NMS in the
model). `scripts/model-trials/bell_trial.py` ran it over the four sample clips at confidence ≥ 0.25; with a pose
fixture for the same clip it scores the box **nearest a wrist** (a gym has bells on the rack, all of which the
detector also finds, so "the best box" is the wrong question).

| Clip | Frames | Frames with a bell | Confidence (median, wrist-nearest box) | Box within 0.1 of a wrist | Inference (Mac) |
|---|---|---|---|---|---|
| swing-sample-4reps | 165 | 100 % | 0.78 | 52 % | 8.9 ms |
| igor-1h-swing | 593 | 100 % | 0.65 | 70 % | 8.8 ms |
| pistols (bell on the floor, none in hand) | 914 | 100 % | 0.76 | 14 % | 8.8 ms |
| bulgarian (no bell in view) | 1094 | 4 % | 0.26 | – | 8.7 ms |

![YOLO-World finds the swung bell at the top (0.95) and every bell on the rack](images/bell-yolo-world-1h-swing.jpg)
![Two-hand swing at the hinge: the bell between the hands at 0.69, the floor bell at 0.93](images/bell-yolo-world-4reps.jpg)

### Smaller and cheaper: YOLOE nano and the small model at 320 px

Igor: use nano. YOLO-World has no nano, but YOLOE does (`yoloe-26n`, the same generation as the app's
`yolo26n-pose`); exported the same way with the prompt "kettlebell" (5.5 MB). Also the small model at 320 px, for
the cost of a lower resolution. Same trial, wrist-nearest box:

| Model, floor | swing-4reps: bell / on wrists | igor-1h-swing | pistols (floor bell) | bulgarian (no bell) | Inference (Mac) | Size |
|---|---|---|---|---|---|---|
| World small 640, 0.25 | 100 % / 52 % | 100 % / 70 % | 100 % / 14 % | 4 % | 8.9 ms | 24 MB |
| World small 320, 0.25 | 100 % / 38 % | 100 % / 36 % | 1 % | 0 % | 2.7 ms | 24 MB |
| **YOLOE nano 640, 0.25** | 100 % / **79 %** | 100 % / **70 %** | 100 % / 10 % | 86 % (median 0.30) | 7.0 ms | **5.5 MB** |
| YOLOE nano 640, 0.40 | 100 % / 61 % | 100 % / 47 % | 100 % / 9 % | 19 % (median 0.44) | 7.0 ms | 5.5 MB |

- The nano keeps the swung bell on the wrists as well as or better than the small model, at lower confidence
  (about 0.5 on the bell in hand, 0.9 on the still bells on the rack: motion blur costs it). Raising the floor to
  0.4 loses in-hand frames; better to keep 0.25 and let a **tracker** carry the bell across frames (start a track
  on a confident box near the wrists, keep it on low-confidence boxes that continue its motion).
- The nano's false positives on the bell-less clip are intermittent low-confidence boxes (none on the two frames
  rendered at 0.15); a tracker that needs a box near the wrists for several frames does not start on them.
- 320 px halves nothing that matters: the swung bell is lost far more often. Stay at 640.

**Verdict: YOLOE nano at 640, floor 0.25, with a wrist-anchored tracker.** Same model family as the pose model,
a fifth of the small model's size, and the in-hand bell is found at least as often.

What the numbers say (small model, first trial):

- **It sees the bell.** Every frame of both swing clips has a kettlebell box, the swung bell reads 0.65–0.95 at the
  top and 0.69 at the hinge, and it lands on the wrists in 52–70 % of frames. The misses are mostly the hinge, where
  the bell hangs between the legs and the box nearest the wrists is a rack bell; a tracker that follows the box from
  frame to frame (the bell that moves with the wrists) would resolve those.
- **It is honest about absence**: the split-squat clip, with no bell in view, gets a box in 4 % of frames at 0.26.
- **Rack bells are the noise**, not false positives: they are real bells. Picking the box by wrist distance (or by
  motion) is the whole disambiguation.
- Inference on the Mac is 9 ms; the phone's Neural Engine is the real measure and is not yet taken.

## 2026-09-12: plumbing built (step 1)

- `BellDetector` (ExerciseCore, Vision) runs the nano on a frame and parses its end-to-end output itself: the
  export is a segmentation model, so each row is [x1, y1, x2, y2, conf, class, 32 mask coefficients] in the 640 px
  letterboxed input plus a mask prototype tensor; the Ultralytics SDK's detector expects six columns and cannot
  read it. Rows map back with the pose model's letterbox math. The mask outputs are computed and thrown away: a
  detect-only export would be cheaper and is the first thing to try if the phone's cost is high.
- `BellSighting` per frame (box, confidence, mean colour of the box's middle via `CIAreaAverage`), stored in the
  track and in fixtures; `BellTracker` in the pipeline picks the bell in play (starts on a box ≥ 0.5 within 0.12 of
  a wrist, follows within 0.1 at ≥ 0.25, lost after 10 unseen frames); `BellColor.weightKg` maps a vivid hue to
  the competition code. `BellTests` cover the tracker and the colours.
- The app runs it in the offline pass only and logs `bell_frames`, `bell_avg_infer_ms`, `bell_seen` in
  `offline_pass`; a dot in the bell's colour rides on the tracked bell in playback. `posetrack` runs it on the Mac
  and `--poses-from` adds bells to a fixture without touching its poses: the four sample fixtures now carry bells.
- Mac, 4-rep clip: bell in play in 87 % of frames; the pass went from 60 to 40 fps with the detector (release
  build, Vision on the Mac's GPU/ANE). Simulator (CPU): pose 27 ms, detector 74 ms per frame, 9 fps for the pass.
  Phone cost: pending the first `offline_pass` with the detector bundled. Commit 3b997e1.

## 2026-09-12: other equipment (dumbbells, barbells, bench) with the same nano

Igor: can it extract dumbbells and barbells too, and whatever helps the Bulgarian split squat? With YOLOE the
classes are text prompts fixed at export, so a wider vocabulary costs nothing per frame. Exported the nano with
"kettlebell, dumbbell, barbell, weight plate, bench, plyo box" (`export_bell_detector.py yoloe 26n 640
kettlebell,dumbbell,barbell,weight plate,bench,plyo box`) and ran `equipment_trial.py`:

| Clip | kettlebell | dumbbell | barbell | weight plate | bench | plyo box |
|---|---|---|---|---|---|---|
| swing-4reps | 100 % (0.54) | – | – | – | – | – |
| igor-1h-swing | 100 % (0.91) | – | – | – | – | – |
| pistols | 100 % (0.77) | – | – | 65 % (0.47) | – | – |
| bulgarian | 86 % (0.34) | – | – | – | – | – |

![Bulgarian split squat: the bench under the rear foot and the dumbbell rack behind, none detected](images/equipment-nano-bulgarian.jpg)
![Pistol: "weight plate" is the kettlebell's own handle; the plates on the wall rack are not found](images/equipment-nano-pistols.jpg)

- The kettlebell class is as good as in the single-class export (better on the one-hand clip), so a wider
  vocabulary does not cost the bell anything.
- The other classes did not deliver on these clips: the Bulgarian clip (464 × 848, dim) has a bench under the rear
  foot and a dumbbell rack in the background and the nano found neither, even at 0.15; "weight plate" in the pistol
  clip is the kettlebell's handle, while the real plates on the wall rack are missed. No clip has a dumbbell or a
  barbell in hand, so the in-hand case is untested.
- Decision: the bundled model stays single-class kettlebell for now. To revisit: record one Bulgarian set with a
  dumbbell in each hand and the bench in frame at full resolution, then try the nano and the small (`26s`) with
  those prompts on it. If dumbbells in hand detect, the tracker generalises to "the weight that moves with the
  wrists" and the bench becomes a second signal for the split-squat detector (rear foot on a bench).

## 2026-09-12: the first phone run crashed; three exports of one checkpoint (#43)

The first re-run of a stored get-up from its video crashed the app (the log stops after `recents_rerun`), and the
Mac reproduced it on the same clip (exported from Photos with `osascript`): `EXC_BAD_ACCESS` in `memmove` on
Vision's transformer queue at frame 398, every run, stack not unwindable. Pose-only ran the whole clip at 124 fps.
Isolation by switches in `posetrack`: colour sampling off, copied sample buffers, detector on CPU: still crashes;
detector on GPU: runs, and Core ML prints "Invalid blob shape: data-dependent shapes were disabled: gather_nd". A
half-second cut around frame 398 and a blank clip both run clean, so the trigger is runtime state after hundreds of
frames of varying output sizes, not one frame's content.

What the Ultralytics exporter does with `nms` for a YOLO26 checkpoint, which carries two heads:

| `export(nms=…)` | Graph | Output | Verdict |
|---|---|---|---|
| `True` | dense one-to-many head + an NMS op traced into the graph | rows per frame vary | the crash above; GPU refuses it |
| `False` | the end-to-end one-to-one head with top-300 | `[1, 300, 38]`, static | static, but this head scores the blurred bell in hand at 0.08 where the dense head says 0.39 |
| `None` | dense one-to-many head, no NMS op | `[1, 37, 8400]` (4 box, 1 score, 32 mask coefficients), static | **bundled**: `BellDetector.parseDense` decodes it and suppresses overlaps in Swift |

Also found on the way: the phone's Neural Engine hands the output back as Float16 while the Mac gives Float32;
`BellDetector` now reads by data type (`BellDetectorParseTests`). And a self-inflicted detour: a second export
moved *into* the first package's folder instead of replacing it, so one run loaded the old model.

### The phone, after the export fix: two more leaks and two more stops

- The dense-model build still died within a second of the pass, with no signal caught and no MetricKit report: a
  kill from outside the process. `offline_progress` (memory every 60 frames) settled it: 132 MB at frame 1, 3367 MB
  at frame 421 with 9 MB left. Nine MB a frame is one 1080 × 1920 BGRA frame: `CIImage(cvPixelBuffer:)` +
  `CIAreaAverage` on a shared `CIContext` kept every frame alive on iOS (the Mac peaked at 229 MB). The sampler
  reads the BGRA bytes now.
- Then ~1.4 MB a frame: Vision's observations and the two output tensors are autoreleased and a detached loop never
  drains its pool; `autoreleasepool` per frame. Flat at 73 MB from then on.
- "Model not ready": a set opened in the first second after launch reached the pass before the model loaded (#45);
  the pass waits up to 10 s.
- "Operation Interrupted" at 43 s: auto-lock backgrounded the app mid-pass and AVFoundation stopped the reader
  (#46); the pass holds the idle timer like recording does.

Phone, IMG_4342 (3989 frames), untouched: 91.3 s at 43.7 fps, pose 10.7 ms, detector 12.0 ms, decode 0.35 ms per
frame, footprint 73 MB flat, bell in 2962 frames, 2 reps. Before the detector the same pass ran at ~94 fps: the
second model is the whole cost; decoding is free. Levers, Igor's first: detector only inside the padded rep span
the pose pass finds (this clip ~57 % of frames, saves ~20 s of 91); every second frame with the tracker bridging
(~24 s); a detect-only export without the mask branch (untested).

Tracker after the study (`BellTests`): a box still within 0.02 for 90 frames is a bell at rest, and so is any box
in a grid cell that holds a bell in 60 % of the clip's frames (known before an offline analysis; 30 % caught a
swung bell's own apex); neither is started on or followed. Following also requires the box within 0.2 of a visible
wrist (the bell in play is in the hands by definition) and a colour within 60° of hue of the tracked bell when
both are vivid (45° flipped a dark red bell between orange and yellow readings under gym light). Measured with the
wrist gate off, half the "tracked" frames on the swing clips sat 0.2 or more from any wrist: rack bells, which had
padded the earlier percentages. With the dense head and the gates:

| Clip | Bell in play | Count |
|---|---|---|
| swing-4reps | 83 % | 4 |
| igor-1h-swing | 62 % (28 kg by colour) | 9 |
| pistols (floor bell) | 1 % | 6 |
| bulgarian | 6 % | 8 |
| tgu-phone-2min (IMG_4342) | 47 % (28 kg by colour) | 2 |

Compute plan on the Mac (`POSETRACK_PLAN=1`): pose model 303 ops on the Neural Engine, 19 CPU; detector 316
and 2; the rest are constants. The phone logs the same as `model_plan` (#44).

## 2026-09-12: parked

Igor: "a lot of fun, but it didn't really make anything particularly better; disable it for now and get the speed
back." The detector stays bundled and the code stays, off by default (`model_skipped` in the log); `SWING_BELLS=1`
or the `bellDetector` user default turns it on for a trial. Sets analyzed with it keep their bells (a build that
runs fewer models does not re-run them). The pass is back at ~94 fps. What would make it worth turning on is the
plan below: the swing on the bell's path and the get-up's stacking, neither built.

## 2026-09-12 night: the bell in (nearly) every frame it is in the hands (#18)

Igor: get the bell in every frame on the swing and get-up clips, controls (pistols with a floor bell, a
Bulgarian with no bell in view) staying near zero. The lab ran on the Mac with Muse doing the grinding; the
notebook with every hypothesis and result is `~/tmp/agent/notes/2026-09-12-bell-lab-notebook.md`.

**Two questions, measured apart.** For frames with a visible wrist: did the detector put any box within 0.2 of
it (*seen*), and did the tracker report a bell there (*held*). `100 − seen` is the detector's ceiling, the gap is
the tracker's loss. posetrack prints both; the tracker questions then ran on stored fixtures through the real
`BellTracker` in under a second (`TuningReports.testBellTrackerHeldPerFixture` is the durable form), with each
lost frame classed as detector-blind, suppressed as furniture, no confident box to start on, a box too far from
the wrist to start, a gap with no box in reach, or a box in reach refused by a rule.

**Where the frames went (nano 640, floor 0.25, the old tracker):** swings lost most to gaps the detector
left and to the swung bell passing through the floor bell's static cell at the bottom of every hinge; the
get-up lost 18 points to starts (no box at 0.4 while dead, or a good box just outside 0.12 of the wrist) and to
following (the overhead bell reads 0.15–0.25 for whole phases and the follow gate was 0.25).

**What moved the number, in order found** (held %, 4reps / 1h / TGU / pistols / bulgarian, floor 0.15 for the
rows that need it, the 1h clip with a 12-box cap):

| change | 4reps | 1h | TGU | pistols | bulgarian |
|---|---|---|---|---|---|
| old tracker, floor 0.25, cap 6 | 67 | 58 | 47 | 1 | 2 |
| lostAfter 30 + startDistance 0.15 | 67 | 68 | 56 | 1 | 7 |
| + static zones gate starts only | 81 | 69 | 56 | 1 | 2 |
| + followConf 0.15 (floor 0.15) | 96 | 69 | 76 | 1 | 13 |
| + coast 3 frames on the last velocity | 98 | 87 | 80 | 2 | 20 |
| + cap 12 (the 1h gym rack holds more than six confident bells) | 98 | 92 | 80 | 2 | 20 |
| + no start on a flat box under 0.2 of the person's height | 98 | 92 | 80 | 2 | **0** |
| **posetrack on the clips, shipped defaults** | **99** | **93** | **78** | **4** | **0** |

Rejected, with the numbers that rejected them: `startConf` 0.3 (TGU +9 but the Bulgarian 4→21: rack junk
at 0.3–0.4 next to hanging hands; the start gate is what keeps a bell-less clip clean); `stillFrames` 150
(nothing); a wider `stillRadius` (nothing on the Bulgarian, TGU −10: the overhead hold reads as furniture);
predictive follow from the last velocity (1h +3 frames, Bulgarian +2); reporting a track only once it has moved
(the Bulgarian's phantoms wander past 0.05 anyway, the 1h loses 26 points at the slow top of every swing);
coasting 10 frames (the carried box drifts, 4reps 98→83); `followDistance` 0.15 (1h +3, Bulgarian +3).
The Bulgarian phantoms were separated by shape, not place: they start as wide boxes (aspect 1.2–2.3) under
0.19 of the person's height, swing bells are tall (aspect ≤ 0.81), get-up bells are wide but big.

**Models and input sizes** (seen / held with the new tracker): nano at 960 sees the small get-up bell in 94 %
of frames (held 81) but only 41 % of the one-hand swing and holds a phantom in 89 % of the Bulgarian; 26s at
640 holds one in 92 %; 26s at 960 holds the pistols' floor bell in 72 %. Nano at 640 stays. A second package
at 960 for get-ups only is the one thing left on the table there.

**Also learned:** the detector floor never changed *held* on its own (every gate sat above it), it only
relabels the loss; lowering it to 0.15 matters only because `followConf` now sits there. The 1h clip's colour
vote moved from 28 kg to 16 kg with the fuller track: Igor knows which bell that was.

Shipped: `BellTracker.Thresholds` startDistance 0.15, followConf 0.15, lostAfter 30, coastFrames 3,
flatStartMaxHeight 0.2 (zones veto starts only); `BellDetector` minConfidence 0.15, maxSightings 12;
AnalysisVersion 2026-09-12.9. Verified on the host (`BellTests`, the report) and the Mac model rung (the
table's last row); the phone is Igor's.

## Plan (offline only; live and the watch unchanged)

1. **Plumbing**: YOLOE nano in the offline pass, a `bell` box per frame in the pose track (fixtures gain a field),
   the in-hand tracker (the box that moves with the wrists), a bell dot on the video, `posetrack` runs the detector
   too so fixtures come with bells, and `avg_infer_ms` for the second model from the phone's `offline_pass`. Also
   the bell's **colour** from the pixels inside the box (median hue, saturation, value): competition bells are
   colour-coded by weight (8 kg pink, 12 blue, 16 yellow, 20 purple, 24 green, 28 orange, 32 red, 36 lilac, 40
   white, 44 silver, 48 gold), so a coloured bell maps to a weight; a cast-iron bell reads black and gets no
   weight. Igor's bells in the sample clips are dark, so the mapping needs a coloured bell on the phone to verify.
2. **Swing v2**: bottom and top from the bell's path, a rep needs the bell in the hands and real travel (walk-in,
   pick-up and park fall out), apex height and float at the top as metrics; arm thresholds become quality only.
3. **Get-up v2**: bell-over-shoulder offset per stage, bell stillness through the transitions, bell overhead the
   whole rep, side from the bell.
