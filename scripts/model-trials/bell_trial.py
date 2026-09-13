# /// script
# requires-python = ">=3.10,<3.13"
# dependencies = ["ultralytics", "coremltools", "numpy<=2.3.5", "opencv-python"]
# ///
"""Rung 1.5 model trial: run a Core ML kettlebell detector over sample clips and say whether it finds the bell.

Usage: bell_trial.py <model.mlpackage> <video.mp4>[:<fixture.json>] ...

Per clip: frames, frames with a detection at or above the confidence floor, median confidence, inference time, and,
when a pose fixture for the same clip is given, how far the box nearest a wrist sits from it (fraction of the
frame) - the bell is in the hands for swings, so a small distance means the detector saw the bell being swung, not
one on the rack.
"""
import json
import statistics
import sys
import time

import cv2
import numpy as np
from ultralytics import YOLO

CONF = 0.25
WRISTS = (9, 10)  # COCO left/right wrist


def wrists_by_time(fixture):
    out = []
    for f in json.load(open(fixture))["frames"]:
        pose = f.get("pose")
        if not pose:
            out.append((f["time"], None))
            continue
        pts = [(p["x"], p["y"]) for p in pose["xyn"]]
        out.append((f["time"], [pts[i] for i in WRISTS]))
    return out


def nearest(items, t):
    return min(items, key=lambda it: abs(it[0] - t))[1] if items else None


def main():
    model = YOLO(sys.argv[1], task="detect")
    print(f"model {sys.argv[1]}  names {model.names}")
    for arg in sys.argv[2:]:
        video, _, fixture = arg.partition(":")
        cap = cv2.VideoCapture(video)
        fps = cap.get(cv2.CAP_PROP_FPS) or 30
        cap.release()
        wrists = wrists_by_time(fixture) if fixture else []
        confs, dists, infer = [], [], []
        frames = 0
        for i, r in enumerate(model.predict(source=video, conf=CONF, stream=True, verbose=False, imgsz=640)):
            frames += 1
            infer.append(r.speed["inference"])
            if len(r.boxes) == 0:
                continue
            w = nearest(wrists, i / fps)
            # A gym has bells on the rack too: with a fixture, the bell that matters is the box nearest a wrist;
            # without one, the most confident box.
            best = None
            for c, (x1, y1, x2, y2) in zip(r.boxes.conf.tolist(), r.boxes.xyxyn.tolist()):
                cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
                if w:
                    # The app's frame may be the rotated one; take the best of the 90° readings.
                    d = min(
                        min(np.hypot(cx - wx, cy - wy) for wx, wy in w),
                        min(np.hypot((1 - cy) - wx, cx - wy) for wx, wy in w),
                        min(np.hypot(cy - wx, (1 - cx) - wy) for wx, wy in w),
                    )
                    key = d
                else:
                    d, key = None, -c
                if best is None or key < best[0]:
                    best = (key, c, d)
            confs.append(float(best[1]))
            if best[2] is not None:
                dists.append(float(best[2]))
        name = video.rsplit("/", 1)[-1]
        det = len(confs)
        line = f"{name:26s} frames {frames:5d}  detected {det:5d} ({100 * det / max(frames, 1):3.0f}%)"
        line += f"  conf median {statistics.median(confs):.2f}" if confs else "  conf -"
        line += f"  infer {statistics.median(infer):.1f} ms" if infer else ""
        if dists:
            near = sum(d < 0.1 for d in dists)
            line += f"  box-to-wrist median {statistics.median(dists):.3f}, within 0.1: {100 * near / len(dists):3.0f}%"
        print(line)


if __name__ == "__main__":
    main()
