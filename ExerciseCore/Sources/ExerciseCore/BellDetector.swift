// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Runs the kettlebell detector (#18) on a frame and returns every bell it saw, with the mean colour inside each
//  box. Shared by the app's offline pass and the Mac tool, so a fixture's bells are exactly what the phone sees.
//
//  The model is an Ultralytics end-to-end export (YOLOE nano, prompt "kettlebell", NMS inside): one output of
//  [1, max_det, 6 + extras] rows (x1, y1, x2, y2 in the letterboxed 640 × 640 input, confidence, class, then mask
//  coefficients for the segmentation head, which are ignored) plus a mask prototype tensor, also ignored. Rows
//  are mapped back to the image with the same letterbox math the pose model uses.

#if canImport(Vision)
  import CoreGraphics
  import CoreML
  import CoreVideo
  import Foundation
  import Vision

  /// Vision's scaleFit letterbox, inverted: model-input pixels back to source-image pixels
  /// (BasePredictor.letterboxTransform / inputPoint in the Ultralytics SDK).
  public struct Letterbox {
    public let gain: CGFloat
    public let padX: CGFloat
    public let padY: CGFloat
    public let inputSize: CGSize

    public init?(inputSize: CGSize, model: (width: Int, height: Int)) {
      let mw = CGFloat(model.width), mh = CGFloat(model.height)
      guard inputSize.width > 0, inputSize.height > 0 else { return nil }
      gain = min(mh / inputSize.height, mw / inputSize.width)
      let rw = (inputSize.width * gain).rounded(), rh = (inputSize.height * gain).rounded()
      padX = ((mw - rw) / 2 - 0.1).rounded()
      padY = ((mh - rh) / 2 - 0.1).rounded()
      self.inputSize = inputSize
    }

    public func point(_ p: CGPoint) -> CGPoint {
      let x = (p.x - padX) / gain, y = (p.y - padY) / gain
      return CGPoint(x: min(max(x, 0), inputSize.width), y: min(max(y, 0), inputSize.height))
    }
  }

  public final class BellDetector {
    public let model: VNCoreMLModel
    public let compiledModelURL: URL
    public let inputSize: (width: Int, height: Int)
    public var minConfidence: Float = 0.25
    /// Sightings kept per frame, most confident first (a rack holds many bells; six is plenty for the tracker).
    public var maxSightings = 6
    /// Milliseconds spent in the last `detect` call, for the session log.
    public private(set) var lastInferenceMs = 0.0
    /// Whether each box's mean colour is sampled from the pixels (off for experiments).
    public var samplesColor = true

    /// `compiledModelURL` is an .mlmodelc (the app bundle compiles the package; the Mac tool compiles it itself).
    public init(compiledModelURL: URL, computeUnits: MLComputeUnits = .all) throws {
      let config = MLModelConfiguration()
      config.computeUnits = computeUnits
      let mlModel = try MLModel(contentsOf: compiledModelURL, configuration: config)
      guard let image = mlModel.modelDescription.inputDescriptionsByName.values.first(where: { $0.type == .image }),
        let constraint = image.imageConstraint
      else { throw NSError(domain: "BellDetector", code: 1, userInfo: [NSLocalizedDescriptionKey: "model has no image input"]) }
      inputSize = (constraint.pixelsWide, constraint.pixelsHigh)
      model = try VNCoreMLModel(for: mlModel)
      self.compiledModelURL = compiledModelURL
    }

    /// Every bell in the frame, boxes normalized to the image (origin top-left), colours sampled from the pixels.
    public func detect(in pixelBuffer: CVPixelBuffer) -> [BellSighting] {
      let started = Date()
      defer { lastInferenceMs = Date().timeIntervalSince(started) * 1000 }
      // Vision's observations and the output tensors (a 37 × 8400 and a 32 × 160 × 160 per frame) are autoreleased;
      // a background loop over thousands of frames never drains its pool on its own, and the footprint grew
      // ~1.4 MB a frame on the phone until the memory limit (#43). Drain per call.
      return autoreleasepool {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFit
        guard (try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])) != nil else { return [] }
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        guard let letterbox = Letterbox(inputSize: size, model: inputSize) else { return [] }
        let tensors = (request.results ?? []).compactMap { ($0 as? VNCoreMLFeatureValueObservation)?.featureValue.multiArrayValue }
        // Row-major end-to-end output [1, max_det, 6+] or the dense one-to-many head [1, channels, anchors]; the
        // mask prototype tensor [1, 32, 160, 160] is neither.
        guard let tensor = tensors.first(where: { $0.shape.count == 3 }) else { return [] }
        let shape = tensor.shape.map { $0.intValue }
        let parsed = shape[2] > shape[1] * 4
          ? Self.parseDense(tensor, letterbox: letterbox, minConfidence: minConfidence)
          : Self.parse(tensor, letterbox: letterbox, minConfidence: minConfidence)
        let boxes = Self.suppressOverlaps(parsed)
        return boxes.prefix(maxSightings).map { conf, box in
          BellSighting(box: box, conf: conf, color: samplesColor ? BellColorSampler.averageColor(in: pixelBuffer, box: box) : nil)
        }
      }
    }

    /// The export carries no NMS stage (one with it has data-dependent output shapes, which crashed Core ML on a
    /// frame with no bell), so near-duplicate rows of the same bell are dropped here: most confident first, any
    /// later box overlapping a kept one by more than half its area goes.
    static func suppressOverlaps(_ boxes: [(conf: Float, box: CGRect)], iou: CGFloat = 0.5) -> [(conf: Float, box: CGRect)] {
      var kept: [(conf: Float, box: CGRect)] = []
      for candidate in boxes.sorted(by: { $0.conf > $1.conf }) {
        let duplicate = kept.contains { k in
          let inter = k.box.intersection(candidate.box)
          guard !inter.isNull, inter.width > 0, inter.height > 0 else { return false }
          let union = k.box.width * k.box.height + candidate.box.width * candidate.box.height - inter.width * inter.height
          return union > 0 && inter.width * inter.height / union > iou
        }
        if !duplicate { kept.append(candidate) }
      }
      return kept
    }

    /// The dense head: [1, channels, anchors] with channels = 4 box (centre x, y, width, height in model-input
    /// pixels), one score per class, then mask coefficients. Every anchor is a candidate; the caller suppresses
    /// overlaps. Fixed shape, so Core ML never has to size an output at run time.
    public static func parseDense(_ array: MLMultiArray, letterbox: Letterbox, minConfidence: Float, classes: Int = 1)
      -> [(conf: Float, box: CGRect)]
    {
      let shape = array.shape.map { $0.intValue }
      let strides = array.strides.map { $0.intValue }
      guard shape.count == 3, strides.count == 3, shape[1] >= 4 + classes else { return [] }
      let anchors = shape[2]
      let read = reader(for: array)
      var out: [(Float, CGRect)] = []
      for a in 0..<anchors {
        var conf: Float = 0
        for c in 0..<classes { conf = max(conf, read((4 + c) * strides[1] + a * strides[2])) }
        guard conf >= minConfidence else { continue }
        let cx = CGFloat(read(a * strides[2])), cy = CGFloat(read(strides[1] + a * strides[2]))
        let w = CGFloat(read(2 * strides[1] + a * strides[2])), h = CGFloat(read(3 * strides[1] + a * strides[2]))
        let p1 = letterbox.point(CGPoint(x: cx - w / 2, y: cy - h / 2))
        let p2 = letterbox.point(CGPoint(x: cx + w / 2, y: cy + h / 2))
        let box = CGRect(
          x: p1.x / letterbox.inputSize.width, y: p1.y / letterbox.inputSize.height,
          width: (p2.x - p1.x) / letterbox.inputSize.width, height: (p2.y - p1.y) / letterbox.inputSize.height)
        guard box.width > 0, box.height > 0 else { continue }
        out.append((conf, box))
      }
      return out
    }

    /// Reads a tensor element as Float whatever its storage: Float16 on the phone, Float32 on the Mac.
    static func reader(for array: MLMultiArray) -> (Int) -> Float {
      switch array.dataType {
      case .float16:
        let p = UnsafeMutablePointer<Float16>(OpaquePointer(array.dataPointer))
        return { Float(p[$0]) }
      case .float32:
        let p = UnsafeMutablePointer<Float>(OpaquePointer(array.dataPointer))
        return { p[$0] }
      case .double:
        let p = UnsafeMutablePointer<Double>(OpaquePointer(array.dataPointer))
        return { Float(p[$0]) }
      default:
        return { array[$0].floatValue }
      }
    }

    /// Rows of [x1, y1, x2, y2, conf, class, …] in model-input pixels → normalized image boxes. The tensor is
    /// Float16 on the phone (the export is half precision and the Neural Engine keeps it so) and Float32 on the
    /// Mac; reading it with the wrong width walks off the buffer, which is how the first phone run crashed.
    public static func parse(_ array: MLMultiArray, letterbox: Letterbox, minConfidence: Float) -> [(conf: Float, box: CGRect)] {
      let shape = array.shape.map { $0.intValue }
      let strides = array.strides.map { $0.intValue }
      guard shape.count == 3, strides.count == 3 else { return [] }
      let count = shape[1], width = shape[2]
      guard width >= 6 else { return [] }
      let read = reader(for: array)
      var out: [(Float, CGRect)] = []
      for i in 0..<count {
        let base = i * strides[1]
        let conf = read(base + 4 * strides[2])
        guard conf >= minConfidence else { continue }
        let a = letterbox.point(CGPoint(x: CGFloat(read(base)), y: CGFloat(read(base + strides[2]))))
        let b = letterbox.point(CGPoint(x: CGFloat(read(base + 2 * strides[2])), y: CGFloat(read(base + 3 * strides[2]))))
        let box = CGRect(
          x: a.x / letterbox.inputSize.width, y: a.y / letterbox.inputSize.height,
          width: (b.x - a.x) / letterbox.inputSize.width, height: (b.y - a.y) / letterbox.inputSize.height)
        guard box.width > 0, box.height > 0 else { continue }
        out.append((conf, box))
      }
      return out
    }
  }
#endif
