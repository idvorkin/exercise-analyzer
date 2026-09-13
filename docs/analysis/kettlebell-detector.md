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

What the numbers say:

- **It sees the bell.** Every frame of both swing clips has a kettlebell box, the swung bell reads 0.65–0.95 at the
  top and 0.69 at the hinge, and it lands on the wrists in 52–70 % of frames. The misses are mostly the hinge, where
  the bell hangs between the legs and the box nearest the wrists is a rack bell; a tracker that follows the box from
  frame to frame (the bell that moves with the wrists) would resolve those.
- **It is honest about absence**: the split-squat clip, with no bell in view, gets a box in 4 % of frames at 0.26.
- **Rack bells are the noise**, not false positives: they are real bells. Picking the box by wrist distance (or by
  motion) is the whole disambiguation.
- Inference on the Mac is 9 ms; the phone's Neural Engine is the real measure and is not yet taken.

## Next, if wanted

1. Run the detector in the offline pass only (not live), store a `bell` box per frame in the pose track (fixtures
   gain a field), choose the swung bell as the box that moves with the wrists, and add `bellHeight` to the swing
   metrics: a direct "top" signal that does not depend on arm angle (#16's low-camera problem).
2. Measure `avg_infer_ms` for the second model on the phone before deciding about live.
3. Only then the HUD dot and the get-up's "bell stacked over the wrist".
