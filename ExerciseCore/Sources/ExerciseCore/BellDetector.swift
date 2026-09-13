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
    public let inputSize: (width: Int, height: Int)
    public var minConfidence: Float = 0.25
    /// Sightings kept per frame, most confident first (a rack holds many bells; six is plenty for the tracker).
    public var maxSightings = 6
    /// Milliseconds spent in the last `detect` call, for the session log.
    public private(set) var lastInferenceMs = 0.0

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
    }

    /// Every bell in the frame, boxes normalized to the image (origin top-left), colours sampled from the pixels.
    public func detect(in pixelBuffer: CVPixelBuffer) -> [BellSighting] {
      let started = Date()
      defer { lastInferenceMs = Date().timeIntervalSince(started) * 1000 }
      let request = VNCoreMLRequest(model: model)
      request.imageCropAndScaleOption = .scaleFit
      guard (try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])) != nil else { return [] }
      let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
      guard let letterbox = Letterbox(inputSize: size, model: inputSize) else { return [] }
      let rows = (request.results ?? []).compactMap { ($0 as? VNCoreMLFeatureValueObservation)?.featureValue.multiArrayValue }
        .first { $0.shape.count == 3 && $0.shape[2].intValue >= 6 }
      guard let rows else { return [] }
      let boxes = Self.parse(rows, letterbox: letterbox, minConfidence: minConfidence)
      return boxes.sorted { $0.conf > $1.conf }.prefix(maxSightings).map { conf, box in
        BellSighting(box: box, conf: conf, color: BellColorSampler.averageColor(in: pixelBuffer, box: box))
      }
    }

    /// Rows of [x1, y1, x2, y2, conf, class, …] in model-input pixels → normalized image boxes.
    static func parse(_ array: MLMultiArray, letterbox: Letterbox, minConfidence: Float) -> [(conf: Float, box: CGRect)] {
      let shape = array.shape.map { $0.intValue }
      let strides = array.strides.map { $0.intValue }
      let count = shape[1], width = shape[2]
      guard width >= 6 else { return [] }
      let p = UnsafeMutablePointer<Float>(OpaquePointer(array.dataPointer))
      var out: [(Float, CGRect)] = []
      for i in 0..<count {
        let base = i * strides[1]
        let conf = p[base + 4 * strides[2]]
        guard conf >= minConfidence else { continue }
        let a = letterbox.point(CGPoint(x: CGFloat(p[base]), y: CGFloat(p[base + strides[2]])))
        let b = letterbox.point(CGPoint(x: CGFloat(p[base + 2 * strides[2]]), y: CGFloat(p[base + 3 * strides[2]])))
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
