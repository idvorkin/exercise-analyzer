# /// script
# requires-python = ">=3.10,<3.13"
# dependencies = ["ultralytics", "coremltools", "torch", "torchvision", "onnx", "numpy<2", "clip @ git+https://github.com/ultralytics/CLIP.git"]
# ///
"""Export an open-vocabulary YOLO detector with the single class "kettlebell" to Core ML (what the phone runs).

Usage: export_bell_detector.py world [imgsz]        # YOLO-World v2 small (no nano exists)
       export_bell_detector.py yoloe 26n [imgsz] [class,class,...]   # YOLOE, sizes 26n/26s/26m/11s/... (nano exists)
       export_bell_detector.py coco                 # plain COCO yolo11n, a control (COCO has no kettlebell class)

numpy is pinned below 2: coremltools' torch frontend fails in the YOLOE segmentation head otherwise
("only 0-dimensional arrays can be converted to Python scalars"). The CLIP package is what YOLO-World needs for
its text prompt; YOLOE fetches MobileCLIP itself.
"""
import os
import shutil
import sys

from ultralytics import YOLO, YOLOWorld

which = sys.argv[1] if len(sys.argv) > 1 else "world"
if which == "world":
    imgsz = int(sys.argv[2]) if len(sys.argv) > 2 else 640
    m = YOLOWorld("yolov8s-worldv2.pt")
    m.set_classes(["kettlebell"])
    out = m.export(format="coreml", imgsz=imgsz, nms=True, half=True)
    dest = f"yolov8s-worldv2-kettlebell-{imgsz}.mlpackage"
elif which == "yoloe":
    from ultralytics import YOLOE

    size = sys.argv[2] if len(sys.argv) > 2 else "26n"
    imgsz = int(sys.argv[3]) if len(sys.argv) > 3 else 640
    # Extra prompts cost nothing per frame (same network, wider head): "yoloe 26n 640 kettlebell,dumbbell,bench".
    names = sys.argv[4].split(",") if len(sys.argv) > 4 else ["kettlebell"]
    m = YOLOE(f"yoloe-{size}-seg.pt")
    m.set_classes(names, m.get_text_pe(names))
    # nms=None traces the dense one-to-many head with no NMS op: static [1, 4+nc+32, anchors] output, overlaps
    # suppressed in Swift. nms=True bakes an NMS op with data-dependent shapes (crashed Core ML, #43); nms=False
    # exports the end-to-end head, which misses the blurred bell in hand. See docs/analysis/kettlebell-detector.md.
    out = m.export(format="coreml", imgsz=imgsz, nms=None, half=True)
    dest = f"yoloe-{size}-{'-'.join(n.replace(' ', '') for n in names)}-{imgsz}.mlpackage"
else:
    m = YOLO("yolo11n.pt")
    out = m.export(format="coreml", imgsz=640, nms=True, half=True)
    dest = "yolo11n-coco.mlpackage"
if os.path.isdir(dest):
    shutil.rmtree(dest)  # shutil.move into an existing package folder nests it instead of replacing it
shutil.move(str(out), dest)
print("EXPORTED", dest)
