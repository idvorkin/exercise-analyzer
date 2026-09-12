// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  posetrack: run the pose model on a clip on the Mac and analyze it exactly as the phone would, without the
//  simulator. Prints detection and reps; optionally writes the pose track as a host-test fixture.
//
//    swift run -c release posetrack <video> --model ../ExerciseAnalyzer/yolo26n-pose.mlpackage \
//      [--exercise kettlebell-swing] [--fixture out.json] [--conf 0.25]
//
//  Frames are read with the same rotation-applying video composition the app uses, letterboxed by Vision's
//  scaleFit like the SDK, and the end2end output ([1, 300, 57]: xyxy, conf, class, 17 × (x, y, conf)) is mapped
//  back with the SDK's letterbox math, so the poses match the phone's to rounding.

import AVFoundation
import CoreML
import ExerciseCore
import Foundation
import Vision

struct Options {
  var video = ""
  var model = "../ExerciseAnalyzer/yolo26n-pose.mlpackage"
  var exercise: ExerciseKind?
  var fixture: String?
  var confidence: Float = 0.25

  init(_ args: [String]) {
    var i = 0
    while i < args.count {
      let a = args[i]
      func value() -> String { i += 1; return i < args.count ? args[i] : "" }
      switch a {
      case "--model": model = value()
      case "--exercise": exercise = ExerciseKind(rawValue: value())
      case "--fixture": fixture = value()
      case "--conf": confidence = Float(value()) ?? 0.25
      default: if video.isEmpty { video = a }
      }
      i += 1
    }
  }
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
  exit(1)
}

let options = Options(Array(CommandLine.arguments.dropFirst()))
guard !options.video.isEmpty else { fail("usage: posetrack <video> [--model path] [--exercise kind] [--fixture out.json]") }

// MARK: - Model

let modelURL = URL(fileURLWithPath: options.model)
let compiledURL: URL
if modelURL.pathExtension == "mlmodelc" {
  compiledURL = modelURL
} else {
  // Compile once; the compiled model is cached next to the scratch dir keyed by the package's modification date.
  let cacheDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("tmp/agent/skill/posetrack")
  try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
  let stamp = (try? FileManager.default.attributesOfItem(atPath: modelURL.appendingPathComponent("Manifest.json").path)[.modificationDate] as? Date)
    .map { String(Int($0.timeIntervalSince1970)) } ?? "0"
  let cached = cacheDir.appendingPathComponent("\(modelURL.deletingPathExtension().lastPathComponent)-\(stamp).mlmodelc")
  if !FileManager.default.fileExists(atPath: cached.path) {
    let tmp = try MLModel.compileModel(at: modelURL)
    try FileManager.default.moveItem(at: tmp, to: cached)
  }
  compiledURL = cached
}
let config = MLModelConfiguration()
config.computeUnits = .all
let mlModel = try MLModel(contentsOf: compiledURL, configuration: config)
let visionModel = try VNCoreMLModel(for: mlModel)
guard let imageInput = mlModel.modelDescription.inputDescriptionsByName.values.first(where: { $0.type == .image }),
  let constraint = imageInput.imageConstraint
else { fail("model has no image input") }
let modelSize = (width: constraint.pixelsWide, height: constraint.pixelsHigh)

// MARK: - Letterbox mapping (BasePredictor.letterboxTransform / inputPoint)

struct Letterbox {
  let gain: CGFloat, padX: CGFloat, padY: CGFloat, inputSize: CGSize
  init?(inputSize: CGSize, model: (width: Int, height: Int)) {
    let mw = CGFloat(model.width), mh = CGFloat(model.height)
    guard inputSize.width > 0, inputSize.height > 0 else { return nil }
    gain = min(mh / inputSize.height, mw / inputSize.width)
    let rw = (inputSize.width * gain).rounded(), rh = (inputSize.height * gain).rounded()
    padX = ((mw - rw) / 2 - 0.1).rounded()
    padY = ((mh - rh) / 2 - 0.1).rounded()
    self.inputSize = inputSize
  }
  func point(_ p: CGPoint) -> CGPoint {
    let x = (p.x - padX) / gain, y = (p.y - padY) / gain
    return CGPoint(x: min(max(x, 0), inputSize.width), y: min(max(y, 0), inputSize.height))
  }
}

/// The most confident person in one model output, as the app's FrameRecord stores it.
func parse(_ array: MLMultiArray, letterbox: Letterbox, confidence: Float) -> (pose: Pose, box: CGRect)? {
  let shape = array.shape.map { $0.intValue }
  guard shape.count == 3 else { return nil }
  let strides = array.strides.map { $0.intValue }
  let p = array.dataPointer.assumingMemoryBound(to: Float.self)
  let fields = shape[2]
  let kpStart = (fields - 6) % 3 == 0 ? 6 : 5
  let kpCount = (fields - kpStart) / 3
  var best: (conf: Float, index: Int)?
  for i in 0..<shape[1] {
    let conf = p[i * strides[1] + 4 * strides[2]]
    if conf > confidence, conf > (best?.conf ?? 0) { best = (conf, i) }
  }
  guard let best else { return nil }
  let base = best.index * strides[1], fs = strides[2]
  let r1 = letterbox.point(CGPoint(x: CGFloat(p[base]), y: CGFloat(p[base + fs])))
  let r2 = letterbox.point(CGPoint(x: CGFloat(p[base + 2 * fs]), y: CGFloat(p[base + 3 * fs])))
  let size = letterbox.inputSize
  let box = CGRect(
    x: min(r1.x, r2.x) / size.width, y: min(r1.y, r2.y) / size.height,
    width: abs(r2.x - r1.x) / size.width, height: abs(r2.y - r1.y) / size.height)
  var xyn: [PosePoint] = []
  var conf: [Float] = []
  for k in 0..<kpCount {
    let kx = CGFloat(p[base + (kpStart + 3 * k) * fs]), ky = CGFloat(p[base + (kpStart + 3 * k + 1) * fs])
    let point = letterbox.point(CGPoint(x: kx, y: ky))
    xyn.append(PosePoint(x: Float(point.x / size.width), y: Float(point.y / size.height)))
    conf.append(p[base + (kpStart + 3 * k + 2) * fs])
  }
  return (Pose(xyn: xyn, conf: conf, imageSize: size), box)
}

// MARK: - Frames

let asset = AVURLAsset(url: URL(fileURLWithPath: options.video))
let semaphore = DispatchSemaphore(value: 0)
var frames: [FrameRecord] = []
var elapsed = 0.0
Task {
  do {
    guard let track = try await asset.loadTracks(withMediaType: .video).first else { fail("no video track") }
    let composition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderVideoCompositionOutput(
      videoTracks: [track], videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    output.videoComposition = composition
    output.alwaysCopiesSampleData = false
    reader.add(output)
    guard reader.startReading() else { fail("reader: \(String(describing: reader.error))") }
    let started = Date()
    while let sample = output.copyNextSampleBuffer() {
      guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
      let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
      let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
      let request = VNCoreMLRequest(model: visionModel)
      request.imageCropAndScaleOption = .scaleFit
      try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])
      var person: (pose: Pose, box: CGRect)?
      if let observation = request.results?.first as? VNCoreMLFeatureValueObservation,
        let array = observation.featureValue.multiArrayValue, let letterbox = Letterbox(inputSize: size, model: modelSize)
      {
        person = parse(array, letterbox: letterbox, confidence: options.confidence)
      }
      frames.append(FrameRecord(time: time, imageSize: size, pose: person?.pose, box: person?.box, analysis: nil))
      if frames.count % 300 == 0 { FileHandle.standardError.write("  \(frames.count) frames…\n".data(using: .utf8)!) }
    }
    elapsed = Date().timeIntervalSince(started)
  } catch { fail("\(error)") }
  semaphore.signal()
}
semaphore.wait()

// MARK: - Analysis

let detection = ExerciseDetector.detect(frames: frames)
let exercise = options.exercise ?? detection.exercise
let pipeline = AnalysisPipeline.analyze(frames: frames, exercise: exercise)
let withPerson = frames.filter { $0.pose != nil }.count
print(String(format: "%@: %d frames (%d with a person), %.1f s, %.0f fps", options.video, frames.count, withPerson, elapsed, Double(frames.count) / max(elapsed, 0.001)))
print("detected: \(detection.exercise.rawValue) \(detection.confidence)% (\(detection.reason))")
print("analyzed as \(exercise.rawValue): \(pipeline.reps.count) reps")
for rep in pipeline.reps {
  let positions = rep.positions.values.sorted { $0.time < $1.time }
    .map { String(format: "%@ %.2f", $0.phase.prefix(3).description, $0.time) }.joined(separator: " ")
  print(String(format: "  #%2d %3d  %@  %@", rep.number, rep.quality.score, positions, rep.quality.feedback.joined(separator: " · ")))
}

if let path = options.fixture {
  struct StoredPoint: Encodable { let x: Float; let y: Float }
  struct StoredPose: Encodable { let xyn: [StoredPoint]; let conf: [Float] }
  struct StoredFrame: Encodable { let time: Double; let imageSize: [Double]; let box: [[Double]]?; let pose: StoredPose? }
  struct Stored: Encodable { let version = 1; let frames: [StoredFrame] }
  let stored = Stored(frames: frames.map { f in
    StoredFrame(
      time: f.time, imageSize: [Double(f.imageSize.width), Double(f.imageSize.height)],
      box: f.box.map { [[Double($0.minX), Double($0.minY)], [Double($0.width), Double($0.height)]] },
      pose: f.pose.map { StoredPose(xyn: $0.xyn.map { StoredPoint(x: $0.x, y: $0.y) }, conf: $0.conf) })
  })
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.withoutEscapingSlashes]
  try encoder.encode(stored).write(to: URL(fileURLWithPath: path))
  print("fixture written: \(path) (\(frames.count) frames)")
}
