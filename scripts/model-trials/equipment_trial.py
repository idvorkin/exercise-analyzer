# /// script
# requires-python = ">=3.10,<3.13"
# dependencies = ["ultralytics", "coremltools", "numpy<=2.3.5", "opencv-python"]
# ///
"""Per-class detection rate and median confidence of a multi-class Core ML detector over clips.

Usage: equipment_trial.py <model.mlpackage> <video.mp4> ...   (a class's rate is the share of frames with a box
of that class at or above 0.25; look at rendered frames before believing a class, see docs/analysis)."""
import statistics, sys
from collections import defaultdict
from ultralytics import YOLO
model = YOLO(sys.argv[1], task="detect")
names = model.names
print("classes:", names)
for video in sys.argv[2:]:
    frames = 0; seen = defaultdict(list)
    for r in model.predict(source=video, conf=0.25, stream=True, verbose=False, imgsz=640):
        frames += 1
        best = {}
        for c, k in zip(r.boxes.conf.tolist(), r.boxes.cls.tolist()):
            best[int(k)] = max(best.get(int(k), 0), c)
        for k, c in best.items(): seen[k].append(c)
    parts = [f"{names[k]}: {100*len(v)//frames}% (conf {statistics.median(v):.2f})" for k, v in sorted(seen.items())]
    print(f"{video.rsplit('/',1)[-1]:26s} {frames:5d} frames  " + "; ".join(parts))
