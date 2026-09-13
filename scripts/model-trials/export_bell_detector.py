# /// script
# requires-python = ">=3.10,<3.13"
# dependencies = ["ultralytics", "coremltools", "torch", "torchvision", "onnx", "clip @ git+https://github.com/ultralytics/CLIP.git"]
# ///
"""Export open-vocabulary YOLO detectors with the single class "kettlebell" to Core ML (the format the phone runs)."""
import sys
from ultralytics import YOLO, YOLOWorld

which = sys.argv[1] if len(sys.argv) > 1 else "world"
if which == "world":
    m = YOLOWorld("yolov8s-worldv2.pt")
    m.set_classes(["kettlebell"])
    out = m.export(format="coreml", imgsz=640, nms=True, half=True)
elif which == "yoloe":
    from ultralytics import YOLOE
    m = YOLOE("yoloe-11s-seg.pt")
    names = ["kettlebell"]
    m.set_classes(names, m.get_text_pe(names))
    out = m.export(format="coreml", imgsz=640, nms=True, half=True)
else:
    m = YOLO("yolo11n.pt")  # plain COCO detector, for the "does anything fire on the bell" control
    out = m.export(format="coreml", imgsz=640, nms=True, half=True)
print("EXPORTED", out)
