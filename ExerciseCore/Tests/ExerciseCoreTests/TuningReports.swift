// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Not assertions: these print how an analyzer behaves on a fixture under different thresholds, for tuning on
//  the Mac against real sets. Run with `swift test --filter TuningReports`.

import CoreGraphics
import XCTest

@testable import ExerciseCore

final class TuningReports: XCTestCase {
  private func report(_ label: String, _ pipeline: AnalysisPipeline) {
    let lines = pipeline.reps.map { rep -> String in
      let times = rep.positions.values.sorted { $0.time < $1.time }
      let phases = times.map { String(format: "%@ %.1f", $0.phase.prefix(3).description, $0.time) }.joined(separator: " ")
      return String(format: "  #%d %3d  %@", rep.number, rep.quality.score, phases)
    }
    print("\(label): \(pipeline.reps.count) reps\n" + lines.joined(separator: "\n"))
  }

  func testBulgarianPhoneSetUnderThresholds() throws {
    let frames = try Fixture(name: "bulgarian-phone", expectedExercise: .bulgarianSplitSquat, expectedReps: 0, humanVerified: false).frames()
    let knees = frames.compactMap { $0.pose }.map { pose -> Double in
      let skeleton = BodySkeleton(pose: pose)
      return max(skeleton.kneeAngle(.left), skeleton.kneeAngle(.right))
    }.sorted()
    print(String(format: "front-ish knee p10 %.0f p50 %.0f p90 %.0f p97 %.0f", knees[knees.count / 10], knees[knees.count / 2], knees[knees.count * 9 / 10], knees[knees.count * 97 / 100]))

    var current = BulgarianSplitSquatThresholds()
    report("head-travel defaults", analyze(frames, current))
    current.descendFraction = 0.07
    report("descend at 7% of leg length", analyze(frames, current))
    current.descendFraction = 0.14
    report("descend at 14% of leg length", analyze(frames, current))
  }

  func testBulgarianTenRepSetTrace() throws {
    let frames = try Fixture(name: "bulgarian-10reps", expectedExercise: .bulgarianSplitSquat, expectedReps: 10, humanVerified: false).frames()
    report("bulgarian-10reps defaults", analyze(frames, BulgarianSplitSquatThresholds()))
  }

  private func analyze(_ frames: [FrameRecord], _ thresholds: BulgarianSplitSquatThresholds) -> AnalysisPipeline {
    let analyzer = BulgarianSplitSquatAnalyzer(thresholds: thresholds)
    var transitions: [String] = []
    analyzer.trace = { transitions.append($0) }
    let pipeline = AnalysisPipeline(exercise: .bulgarianSplitSquat, analyzer: analyzer)
    for frame in frames { pipeline.process(extracted: frame) { nil } }
    print(transitions.map { "    " + $0 }.joined(separator: "\n"))
    return pipeline
  }
}

extension TuningReports {
  /// Every swing fixture's reps with phase times, completion time, and quality metrics. A rep whose span is far
  /// longer than its neighbours' (~1.2 s) was assembled from setup or put-down frames (issue #4).
  func testSwingRepTraces() throws {
    for fixture in Fixture.all where fixture.expectedExercise == .kettlebellSwing {
      let frames = try fixture.frames()
      let pipeline = AnalysisPipeline.analyze(frames: frames, exercise: .kettlebellSwing)
      let completions = pipeline.track.frames.filter { $0.analysis?.completedRep != nil }.map(\.time)
      var lines: [String] = []
      for (rep, done) in zip(pipeline.reps, completions) {
        let p = rep.positions
        let q = rep.quality.metrics
        lines.append(String(format: "  #%2d top %5.2f con %5.2f bot %5.2f rel %5.2f done %5.2f  span %4.2f  hinge %3.0f lock %3.0f kneeFlex %3.0f  topArm %3.0f topWrist %5.0f",
          rep.number, p["top"]?.time ?? 0, p["connect"]?.time ?? 0, p["bottom"]?.time ?? 0, p["release"]?.time ?? 0, done,
          done - (p["top"]?.time ?? 0), q["hingeDepth"] ?? 0, q["lockoutAngle"] ?? 0, q["kneeFlexion"] ?? 0,
          p["top"]?.metrics["arm"] ?? 0, p["top"]?.metrics["wristHeight"] ?? 0))
      }
      print("\(fixture.name): \(pipeline.reps.count) reps\n" + lines.joined(separator: "\n"))
    }
  }

  /// Raw signals for a fixture at ~4 Hz, plus a naive rep count from smoothed knee-angle dips.
  func testBulgarianPhoneSignals() throws {
    let frames = try Fixture(name: "bulgarian-phone", expectedExercise: .bulgarianSplitSquat, expectedReps: 0, humanVerified: false).frames()
    var lines: [String] = []
    var minKnee: [Double] = []
    for frame in frames {
      guard let pose = frame.pose else { minKnee.append(180); continue }
      let s = BodySkeleton(pose: pose)
      let l = s.kneeAngle(.left), r = s.kneeAngle(.right)
      minKnee.append(min(l > 0 ? l : 180, r > 0 ? r : 180))
      let la = s.ankleY(.left) ?? 0, ra = s.ankleY(.right) ?? 0
      if Int(frame.time * 4) != Int((frame.time - 1.0 / 30) * 4) {
        lines.append(String(format: "%5.1fs  kneeL %3.0f kneeR %3.0f  spine %2.0f  ear %4.0f  ankleL %4.0f ankleR %4.0f  conf L%.1f R%.1f",
          frame.time, l, r, s.spineAngle, s.earY ?? 0, la, ra,
          pose.conf[CocoKeypoint.leftAnkle.rawValue], pose.conf[CocoKeypoint.rightAnkle.rawValue]))
      }
    }
    print(lines.joined(separator: "\n"))
    // Naive rep count: smoothed min-knee dips below 110 separated by rises above 140.
    var smoothed: [Double] = []
    for i in minKnee.indices {
      let window = minKnee[max(0, i - 3)...i]
      smoothed.append(window.reduce(0, +) / Double(window.count))
    }
    var dips = 0, below = false
    for v in smoothed {
      if !below && v < 110 { below = true; dips += 1 }
      if below && v > 140 { below = false }
    }
    print("naive rep count from knee dips: \(dips)")
  }
}

extension TuningReports {
  /// Get-up phase transitions and per-rep quality on the TGU fixture.
  func testTurkishGetUpTrace() throws {
    for fixture in Fixture.all where fixture.expectedExercise == .turkishGetUp { try traceGetUp(fixture) }
  }

  private func traceGetUp(_ fixture: Fixture) throws {
    let frames = try fixture.frames()
    let analyzer = TurkishGetUpAnalyzer()
    var transitions: [String] = []
    analyzer.trace = { transitions.append($0) }
    let pipeline = AnalysisPipeline(exercise: .turkishGetUp, analyzer: analyzer)
    for frame in frames { pipeline.process(extracted: frame) { nil } }
    print(transitions.map { "    " + $0 }.joined(separator: "\n"))
    report(fixture.name, pipeline)
    for rep in pipeline.reps { print("    rep \(rep.number) quality \(rep.quality.metrics) \(rep.quality.feedback)") }
    print("    detection:", ExerciseDetector.detect(frames: frames).reason)
  }

  /// Get-up signals every half second: uprightness, spine lean, hip and knee angles per side, the overhead side,
  /// the support arm's elbow angle, and the torso's angle from the screen's horizontal. This is the table the
  /// staging in docs/analysis/turkish-get-up.md was read from; rerun it when the stages or the camera change.
  func testTurkishGetUpSignals() throws {
    for fixture in Fixture.all where fixture.expectedExercise == .turkishGetUp {
      let frames = try fixture.frames()
      let pipeline = AnalysisPipeline(exercise: .turkishGetUp, analyzer: TurkishGetUpAnalyzer())
      print("=== \(fixture.name)")
      print("    t  phase      up  spine  hipL  hipR kneeL kneeR ovh supElb torso")
      var nextPrint = 0.0
      for frame in frames {
        let result = pipeline.process(extracted: frame) { nil }
        guard frame.time >= nextPrint, let pose = frame.pose else { continue }
        nextPrint += 0.5
        let s = BodySkeleton(pose: pose)
        let overhead = s.overheadArmSide
        var supportElbow = 0.0
        if let support = overhead?.other, let sh = s.point(support.shoulder), let el = s.point(support.elbow),
          let wr = s.point(support.wrist)
        {
          supportElbow = Self.angle(sh, vertex: el, wr)
        }
        var torso = 0.0
        if let sh = s.point(.leftShoulder) ?? s.point(.rightShoulder), let hip = s.point(.leftHip) ?? s.point(.rightHip) {
          torso = atan2(Double(hip.y - sh.y), Double(abs(hip.x - sh.x))) * 180 / .pi
        }
        print(
          String(
            format: "%6.1f  %-9@ %5.2f %5.0f %5.0f %5.0f %5.0f %5.0f  %@  %5.0f %5.0f",
            frame.time, (result.analysis?.phase ?? "-") as NSString, s.uprightness ?? -9, s.spineAngle,
            s.hipAngle(.left), s.hipAngle(.right), s.kneeAngle(.left), s.kneeAngle(.right),
            (overhead == .left ? "L" : overhead == .right ? "R" : "-") as NSString, supportElbow, torso))
      }
    }
  }

  private static func angle(_ a: CGPoint, vertex v: CGPoint, _ b: CGPoint) -> Double {
    let v1 = CGVector(dx: a.x - v.x, dy: a.y - v.y), v2 = CGVector(dx: b.x - v.x, dy: b.y - v.y)
    let dot = Double(v1.dx * v2.dx + v1.dy * v2.dy)
    let mag = Double(hypot(v1.dx, v1.dy) * hypot(v2.dx, v2.dy))
    guard mag > 0 else { return 0 }
    return acos(max(-1, min(1, dot / mag))) * 180 / .pi
  }
}
