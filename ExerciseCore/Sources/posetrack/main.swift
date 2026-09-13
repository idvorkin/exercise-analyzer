// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  posetrack: run the pose model on a clip on the Mac and analyze it exactly as the phone would, without the
//  simulator. Prints detection and reps; optionally writes the pose track as a host-test fixture.
//
//    swift run -c release posetrack <video> --model ../ExerciseAnalyzer/yolo26n-pose.mlpackage \
//      [--exercise kettlebell-swing] [--fixture out.json] [--conf 0.25] \
//      [--bell-model ../ExerciseAnalyzer/yoloe-26n-kettlebell.mlpackage | --no-bells] [--poses-from old.json]
//
//  The bell detector (#18) runs on every frame too when its package is present, and the fixture then carries every
//  bell sighting with its mean colour. `--poses-from` keeps an existing fixture's poses and boxes (frame by frame,
//  same clip) and only adds the bells, so a human-verified fixture keeps the exact track it was verified on.
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
  /// Nil for "the package next to the pose model, if it is there"; `--no-bells` sets it to "".
  var bellModel: String?
  var posesFrom: String?

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
      case "--bell-model": bellModel = value()
      case "--no-bells": bellModel = ""
      case "--poses-from": posesFrom = value()
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

/// Compiles a package once; the compiled model is cached under the scratch dir keyed by the package's modification
/// date (an .mlmodelc is used as is).
func compiled(_ modelURL: URL) throws -> URL {
  if modelURL.pathExtension == "mlmodelc" { return modelURL }
  let cacheDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("tmp/agent/skill/posetrack")
  try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
  let stamp = (try? FileManager.default.attributesOfItem(atPath: modelURL.appendingPathComponent("Manifest.json").path)[.modificationDate] as? Date)
    .map { String(Int($0.timeIntervalSince1970)) } ?? "0"
  let cached = cacheDir.appendingPathComponent("\(modelURL.deletingPathExtension().lastPathComponent)-\(stamp).mlmodelc")
  if !FileManager.default.fileExists(atPath: cached.path) {
    let tmp = try MLModel.compileModel(at: modelURL)
    try FileManager.default.moveItem(at: tmp, to: cached)
  }
  return cached
}

let modelURL = URL(fileURLWithPath: options.model)
let config = MLModelConfiguration()
config.computeUnits = .all
let poseCompiled = try compiled(modelURL)
let mlModel = try MLModel(contentsOf: poseCompiled, configuration: config)
let visionModel = try VNCoreMLModel(for: mlModel)

/// The bell detector, when its package is there (a missing default is simply "no bells").
let bellDetector: BellDetector? = try {
  let path: String
  if let given = options.bellModel {
    if given.isEmpty { return nil }
    path = given
    guard FileManager.default.fileExists(atPath: path) else { fail("bell model not found: \(path)") }
  } else {
    path = modelURL.deletingLastPathComponent().appendingPathComponent("yoloe-26n-kettlebell.mlpackage").path
    guard FileManager.default.fileExists(atPath: path) else { return nil }
  }
  let units: MLComputeUnits
  switch ProcessInfo.processInfo.environment["POSETRACK_BELL_UNITS"] {
  case "cpu": units = .cpuOnly
  case "gpu": units = .cpuAndGPU
  default: units = .all
  }
  return try BellDetector(compiledModelURL: try compiled(URL(fileURLWithPath: path)), computeUnits: units)
}()
guard let imageInput = mlModel.modelDescription.inputDescriptionsByName.values.first(where: { $0.type == .image }),
  let constraint = imageInput.imageConstraint
else { fail("model has no image input") }
let modelSize = (width: constraint.pixelsWide, height: constraint.pixelsHigh)

// MARK: - Pose output (Letterbox comes from ExerciseCore's BellDetector.swift)

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

// MARK: - Compute plan (where the ops run on this Mac; the phone logs the same as model_plan)

if ProcessInfo.processInfo.environment["POSETRACK_PLAN"] == "1" {
  let planSemaphore = DispatchSemaphore(value: 0)
  Task {
    let pose = await ModelPlan.summary(compiledModelURL: poseCompiled)
    print("plan yolo26n-pose: \(pose.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))")
    if let bellDetector {
      let bell = await ModelPlan.summary(compiledModelURL: bellDetector.compiledModelURL)
      print("plan bell detector: \(bell.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))")
    }
    planSemaphore.signal()
  }
  planSemaphore.wait()
}

// MARK: - Frames

let asset = AVURLAsset(url: URL(fileURLWithPath: options.video))
let semaphore = DispatchSemaphore(value: 0)
var frames: [FrameRecord] = []
var elapsed = 0.0
let traceTracker: BellTracker = {  // trace only: what the pipeline's tracker will pick
  var t = BellTracker.Thresholds()
  if let hand = ProcessInfo.processInfo.environment["POSETRACK_HAND"].flatMap(Double.init) { t.handDistance = hand }
  return BellTracker(thresholds: t)
}()
Task {
  do {
    guard let track = try await asset.loadTracks(withMediaType: .video).first else { fail("no video track") }
    let composition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderVideoCompositionOutput(
      videoTracks: [track], videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    output.videoComposition = composition
    output.alwaysCopiesSampleData = ProcessInfo.processInfo.environment["POSETRACK_COPY_SAMPLES"] == "1"
    bellDetector?.samplesColor = ProcessInfo.processInfo.environment["POSETRACK_NO_COLOR"] != "1"
    reader.add(output)
    guard reader.startReading() else { fail("reader: \(String(describing: reader.error))") }
    let started = Date()
    while let sample = output.copyNextSampleBuffer() {
      guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
      let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
      let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
      if frames.isEmpty {
        let f = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let fourcc = String(bytes: [UInt8(f >> 24 & 0xff), UInt8(f >> 16 & 0xff), UInt8(f >> 8 & 0xff), UInt8(f & 0xff)], encoding: .ascii) ?? "?"
        FileHandle.standardError.write("  first frame \(Int(size.width))×\(Int(size.height)) format \(fourcc) planes \(CVPixelBufferGetPlaneCount(pixelBuffer))\n".data(using: .utf8)!)
      }
      let request = VNCoreMLRequest(model: visionModel)
      request.imageCropAndScaleOption = .scaleFit
      try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]).perform([request])
      var person: (pose: Pose, box: CGRect)?
      if let observation = request.results?.first as? VNCoreMLFeatureValueObservation,
        let array = observation.featureValue.multiArrayValue, let letterbox = Letterbox(inputSize: size, model: modelSize)
      {
        person = parse(array, letterbox: letterbox, confidence: options.confidence)
      }
      let bells = bellDetector?.detect(in: pixelBuffer) ?? []
      if ProcessInfo.processInfo.environment["POSETRACK_TRACE"] == "1" {
        let tracked = traceTracker.track(bells, pose: person?.pose)
        let wrists = person.map { p in [9, 10].map { String(format: "%.2f,%.2f", p.pose.xyn[$0].x, p.pose.xyn[$0].y) }.joined(separator: "/") } ?? "-"
        let line = "  frame \(frames.count) t=\(String(format: "%.2f", time)) bells=\(bells.count) \(bells.prefix(3).map { String(format: "%.2f@%.2f,%.2f", $0.conf, $0.box.midX, $0.box.midY) }.joined(separator: " ")) wrists \(wrists) tracked \(tracked.map { String(format: "%.2f@%.2f,%.2f", $0.conf, $0.box.midX, $0.box.midY) } ?? "-")\n"
        FileHandle.standardError.write(line.data(using: .utf8)!)
      }
      frames.append(FrameRecord(time: time, imageSize: size, pose: person?.pose, box: person?.box, analysis: nil, bells: bells))
      if frames.count % 300 == 0 { FileHandle.standardError.write("  \(frames.count) frames…\n".data(using: .utf8)!) }
    }
    elapsed = Date().timeIntervalSince(started)
  } catch { fail("\(error)") }
  semaphore.signal()
}
semaphore.wait()

// MARK: - Poses from an existing fixture

if let path = options.posesFrom {
  struct OldPoint: Decodable { let x: Float; let y: Float }
  struct OldPose: Decodable { let xyn: [OldPoint]; let conf: [Float] }
  struct OldFrame: Decodable { let time: Double; let imageSize: [Double]; let box: [[Double]]?; let pose: OldPose? }
  struct Old: Decodable { let frames: [OldFrame] }
  let old = try JSONDecoder().decode(Old.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
  // A phone-made fixture can differ from the Mac decode by a frame, so bells are matched by time, not index.
  let duration = frames.last?.time ?? 0
  guard abs(Double(old.frames.count - frames.count)) <= 2, abs((old.frames.last?.time ?? 0) - duration) < 0.2 else {
    fail("--poses-from \(path) has \(old.frames.count) frames to \(old.frames.last?.time ?? 0) s, this clip \(frames.count) to \(duration) s: not the same clip")
  }
  let byTime = frames
  frames = old.frames.map { o in
    let size = CGSize(width: o.imageSize[0], height: o.imageSize[1])
    let nearest = byTime.min { abs($0.time - o.time) < abs($1.time - o.time) }
    let bells = (nearest.map { abs($0.time - o.time) <= 0.02 } ?? false) ? nearest!.bells : []
    return FrameRecord(
      time: o.time, imageSize: size,
      pose: o.pose.map { Pose(xyn: $0.xyn.map { PosePoint(x: $0.x, y: $0.y) }, conf: $0.conf, imageSize: size) },
      box: o.box.map { CGRect(x: $0[0][0], y: $0[0][1], width: $0[1][0], height: $0[1][1]) },
      analysis: nil, bells: bells)
  }
  print("poses and boxes kept from \(path); bells added to \(frames.filter { !$0.bells.isEmpty }.count) frames")
}

// MARK: - Analysis

let detection = ExerciseDetector.detect(frames: frames)
let exercise = options.exercise ?? detection.exercise
let pipeline = AnalysisPipeline.analyze(frames: frames, exercise: exercise)
let withPerson = frames.filter { $0.pose != nil }.count
let withBell = pipeline.track.frames.filter { $0.bell != nil }.count
print(String(format: "%@: %d frames (%d with a person), %.1f s, %.0f fps", options.video, frames.count, withPerson, elapsed, Double(frames.count) / max(elapsed, 0.001)))
if bellDetector != nil {
  let colors = pipeline.track.frames.compactMap { $0.bell?.color }
  let weights = colors.compactMap(BellColor.weightKg(rgb:))
  let weight = weights.isEmpty ? "no colour code (cast iron?)" : "\(Dictionary(grouping: weights) { $0 }.max { $0.value.count < $1.value.count }!.key) kg by colour"
  print("bell in play in \(withBell) frames (\(frames.count > 0 ? 100 * withBell / frames.count : 0)%), \(weight)")
}
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
  struct StoredBell: Encodable { let box: [[Double]]; let conf: Float; let color: [Float]? }
  struct StoredFrame: Encodable {
    let time: Double; let imageSize: [Double]; let box: [[Double]]?; let pose: StoredPose?; let bells: [StoredBell]?
  }
  struct Stored: Encodable { let version = 1; let frames: [StoredFrame] }
  let stored = Stored(frames: frames.map { f in
    StoredFrame(
      time: f.time, imageSize: [Double(f.imageSize.width), Double(f.imageSize.height)],
      box: f.box.map { [[Double($0.minX), Double($0.minY)], [Double($0.width), Double($0.height)]] },
      pose: f.pose.map { StoredPose(xyn: $0.xyn.map { StoredPoint(x: $0.x, y: $0.y) }, conf: $0.conf) },
      bells: f.bells.isEmpty ? nil : f.bells.map {
        StoredBell(
          box: [[Double($0.box.minX), Double($0.box.minY)], [Double($0.box.width), Double($0.box.height)]],
          conf: $0.conf, color: $0.color.map { $0.map { (($0 * 1000).rounded() / 1000) } })
      })
  })
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.withoutEscapingSlashes]
  try encoder.encode(stored).write(to: URL(fileURLWithPath: path))
  print("fixture written: \(path) (\(frames.count) frames)")
}
