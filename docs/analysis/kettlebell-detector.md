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
