// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Not assertions: these print how an analyzer behaves on a fixture under different thresholds, for tuning on
//  the Mac against real sets. Run with `swift test --filter TuningReports`.

import CoreGraphics
import XCTest

@testable import ExerciseCore

final class TuningReports: XCTestCase {
  /// #119: wide lunges as a share of lowered poses survive long standing/setup footage.
  func testSplitSquatDetectionWithSetup() throws {
    for fixture in Fixture.all {
      let frames = try fixture.frames()
      let detection = ExerciseDetector.detect(frames: frames)
      print(String(format: "%@: %@ %d%%; lunge/all %.3f, lunge/lowered %.3f, wide frames %.0f", fixture.name,
        detection.exercise.rawValue, detection.confidence, detection.stats["lunge_ratio"] ?? 0,
        detection.stats["lunge_low_ratio"] ?? 0, detection.stats["lunge_frames"] ?? 0))
    }
  }

  private func report(_ label: String, _ pipeline: AnalysisPipeline) {
    let lines = pipeline.reps.map { rep -> String in
      let times = rep.positions.values.sorted { $0.time < $1.time }
      let phases = times.map { String(format: "%@ %.1f", $0.phase.prefix(3).description, $0.time) }.joined(separator: " ")
      let lost = rep.quality.score < 100 ? "  " + rep.quality.feedback.joined(separator: "; ") : ""
      return String(format: "  #%d %3d  %@%@", rep.number, rep.quality.score, phases, lost)
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

  /// #132: Igor's 4CF19A9A set (8 reps, verified) traced, and the two new gates swept over every Bulgarian track:
  /// how deep a dip must go (`minDepthFraction`) and how long the rear foot must be up before a rep may start
  /// (`minSetUpSeconds`).
  func testBulgarianSetupAndWobbleSweep() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "bulgarian-split-squat-20260909-98B26725", withExtension: "json", subdirectory: "Fixtures/tracks"))
    var tracks = try Fixture.all.filter { $0.expectedExercise == .bulgarianSplitSquat }.map { ($0.name, try $0.frames()) }
    tracks.append(("98B26725 (archived, 8)", try Fixture.frames(at: url)))
    report("bulgarian-4CF19A9A-phone defaults", analyze(tracks[2].1, BulgarianSplitSquatThresholds()))
    for depth in [0.0, 0.15, 0.2, 0.3] {
      for setUp in [0.0, 1.0, 1.5, 2.5] {
        var t = BulgarianSplitSquatThresholds()
        t.minDepthFraction = depth
        t.minSetUpSeconds = setUp
        let counts = tracks.map { "\($0.0.prefix(22)) \(analyze($0.1, t).reps.count)" }.joined(separator: " · ")
        print(String(format: "  depth %.2f setUp %.1f s: ", depth, setUp) + counts)
      }
    }
  }

  /// #134: every Bulgarian fixture counted without its bench boxes, and with them at each depth into the box that
  /// still counts as on top. 7424BEDD (Igor: 6) needs the bench; half the box counted 4CF19A9A's setup (9).
  func testBulgarianBenchSweep() throws {
    var tracks = try Fixture.all.filter { $0.expectedExercise == .bulgarianSplitSquat }.map { ($0, try $0.frames()) }
    // The archived Bulgarian sets as the phone stored them (bench boxes from the phone's own detector), count unknown.
    let dir = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/tracks", withExtension: nil))
    for url in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
    where url.lastPathComponent.hasPrefix("bulgarian-split-squat-") {
      let name = "arch-" + url.deletingPathExtension().lastPathComponent.suffix(8)
      tracks.append((Fixture(name: name, expectedExercise: .bulgarianSplitSquat, expectedReps: -1, humanVerified: false), try Fixture.frames(at: url)))
    }
    report("bulgarian-7424BEDD-phone defaults", analyze(tracks.first { $0.0.name.contains("7424BEDD") }!.1, BulgarianSplitSquatThresholds()))
    func count(_ frames: [FrameRecord], _ t: BulgarianSplitSquatThresholds) -> Int {
      let pipeline = AnalysisPipeline(exercise: .bulgarianSplitSquat, analyzer: BulgarianSplitSquatAnalyzer(thresholds: t))
      for frame in frames { pipeline.process(extracted: frame) { nil } }
      return pipeline.reps.count
    }
    let stripped = tracks.map { f, frames in
      (f, frames.map { FrameRecord(time: $0.time, imageSize: $0.imageSize, pose: $0.pose, box: $0.box, analysis: nil, bells: $0.bells) })
    }
    print("  no bench: " + stripped.map { "\($0.0.name.prefix(22)) \(count($0.1, BulgarianSplitSquatThresholds()))/\($0.0.expectedReps)" }.joined(separator: " · "))
    for share in [0.15, 0.25, 0.35, 0.5] {
      var t = BulgarianSplitSquatThresholds()
      t.benchTopShare = share
      print(String(format: "  top %.2f: ", share) + tracks.map { "\($0.0.name.prefix(22)) \(count($0.1, t))/\($0.0.expectedReps)" }.joined(separator: " · "))
    }
  }

  /// The pull-up fixtures (#108): every transition with the shoulders' distance under the bar, the reps, and the
  /// count under other rises, to see how far the setup on the pegs sits from a rep.
  func testPullUpTrace() throws {
    for fixture in Fixture.all where fixture.expectedExercise == .pullUp {
      let frames = try fixture.frames()
      report("\(fixture.name) defaults", analyzePullUp(frames, PullUpThresholds(), printing: true))
      for rise in [0.2, 0.3, 0.45, 0.6, 0.9, 1.1, 1.3] {
        var thresholds = PullUpThresholds()
        thresholds.minRise = rise
        thresholds.startRise = min(thresholds.startRise, rise)
        print(String(format: "  minRise %.2f: %d reps", rise, analyzePullUp(frames, thresholds, printing: false).reps.count))
      }
      for under in [0.2, 0.3, 0.4, 0.5, 0.7, 0.9, 1.2] {
        var thresholds = PullUpThresholds()
        thresholds.letGoUnderBar = under
        print(String(format: "  letGoUnderBar %.2f: %d reps", under, analyzePullUp(frames, thresholds, printing: false).reps.count))
      }
    }
  }

  /// The split squat fixtures (#112): every transition with the hips' height, the reps, and the count under
  /// other depths and stance widths.
  func testSplitSquatTrace() throws {
    for fixture in Fixture.all where fixture.expectedExercise == .splitSquat {
      let frames = try fixture.frames()
      report("\(fixture.name) defaults", analyzeSplitSquat(frames, SplitSquatThresholds(), printing: true))
      for depth in [0.1, 0.15, 0.25, 0.35, 0.4, 0.45] {
        var thresholds = SplitSquatThresholds()
        thresholds.minDepth = depth
        thresholds.descend = min(thresholds.descend, depth)
        print(String(format: "  minDepth %.2f: %d reps", depth, analyzeSplitSquat(frames, thresholds, printing: false).reps.count))
      }
      for split in [0.0, 0.3, 0.6, 1.0, 1.4, 1.8] {
        var thresholds = SplitSquatThresholds()
        thresholds.minSplit = split
        print(String(format: "  minSplit %.2f: %d reps", split, analyzeSplitSquat(frames, thresholds, printing: false).reps.count))
      }
    }
  }

  func testSplitSquatStandingCheckpoints() throws {
    let fixture = try XCTUnwrap(Fixture.all.first { $0.name == "splitsquat-barbell-phone" })
    let frames = try fixture.frames()
    let pipeline = AnalysisPipeline.analyze(frames: frames, exercise: .splitSquat)
    for rep in pipeline.reps {
      let top = try XCTUnwrap(rep.positions["standing"])
      let stance = try XCTUnwrap(BodySkeleton(pose: top.pose).stance)
      print(String(format: "rep %d standing %.2f s hips %.4f bottom %.2f s", rep.number, top.time, stance.hipHeight, rep.positions["bottom"]!.time))
    }
  }

  private func analyzeSplitSquat(_ frames: [FrameRecord], _ thresholds: SplitSquatThresholds, printing: Bool) -> AnalysisPipeline {
    let analyzer = SplitSquatAnalyzer(thresholds: thresholds)
    var transitions: [String] = []
    analyzer.trace = { transitions.append($0) }
    let pipeline = AnalysisPipeline(exercise: .splitSquat, analyzer: analyzer)
    for frame in frames { pipeline.process(extracted: frame) { nil } }
    if printing { print(transitions.map { "    " + $0 }.joined(separator: "\n")) }
    return pipeline
  }

  private func analyzePullUp(_ frames: [FrameRecord], _ thresholds: PullUpThresholds, printing: Bool) -> AnalysisPipeline {
    let analyzer = PullUpAnalyzer(thresholds: thresholds)
    var transitions: [String] = []
    analyzer.trace = { transitions.append($0) }
    let pipeline = AnalysisPipeline(exercise: .pullUp, analyzer: analyzer)
    for frame in frames { pipeline.process(extracted: frame) { nil } }
    if printing { print(transitions.map { "    " + $0 }.joined(separator: "\n")) }
    return pipeline
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

  /// Every frame's swing signals and phase for one archived track, between two times:
  /// `SWING_TRACK=kettlebell-swing-20260918-5C13D496 SWING_FROM=12 SWING_TO=17 swift test --filter testSwingSignals`.
  func testSwingSignals() throws {
    let env = ProcessInfo.processInfo.environment
    guard let name = env["SWING_TRACK"] else { return }
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/tracks"), "missing track \(name)")
    let from = Double(env["SWING_FROM"] ?? "") ?? 0
    let to = Double(env["SWING_TO"] ?? "") ?? .infinity
    let pipeline = AnalysisPipeline.analyze(frames: try Fixture.frames(at: url), exercise: .kettlebellSwing)
    print("\(name): \(pipeline.reps.count) reps")
    for frame in pipeline.track.frames where frame.time >= from && frame.time <= to {
      guard let a = frame.analysis else {
        print(String(format: "  %6.2f  no pose", frame.time))
        continue
      }
      let m = a.metrics
      print(String(format: "  %6.2f  %-8@ rep %2d  arm %4.0f spine %4.0f hip %4.0f knee %4.0f wrist %5.0f%@",
        frame.time, a.phase, a.repCount, m["arm"] ?? 0, m["spine"] ?? 0, m["hip"] ?? 0, m["knee"] ?? 0, m["wristHeight"] ?? 0,
        a.completedRep != nil ? "  REP" : ""))
    }
  }

  /// Every swing fixture's count under a range of `ballisticTopArmMin` (#97): the cut-off that decides whether
  /// a standing frame right after the release is a top (40 = `topArmMin`, the rule before #97).
  /// `swift test --filter testSwingTopArmSweep`; `SWING_TOP_HIP=166` runs the same table under another
  /// `topHipMin`, `SWING_MAX_REP=3` under another `maxRepDuration`, `SWING_BALLISTIC=0.6` under another
  /// `ballisticReleaseMax`. The archived phone tracks follow the fixtures (no known answer: watch for a count
  /// that moves).
  func testSwingTopArmSweep() throws {
    let env = ProcessInfo.processInfo.environment
    let topHip = Double(env["SWING_TOP_HIP"] ?? ""), maxRep = Double(env["SWING_MAX_REP"] ?? "")
    let ballistic = Double(env["SWING_BALLISTIC"] ?? "")
    let values = [40.0, 38, 36, 34, 32, 30, 28]
    func row(_ name: String, _ want: String, _ frames: [FrameRecord]) {
      let counts = values.map { value -> Int in
        var thresholds = SwingThresholds()
        thresholds.ballisticTopArmMin = value
        if let topHip { thresholds.topHipMin = topHip }
        if let maxRep { thresholds.maxRepDuration = maxRep }
        if let ballistic { thresholds.ballisticReleaseMax = ballistic }
        let pipeline = AnalysisPipeline(exercise: .kettlebellSwing, analyzer: KettlebellSwingAnalyzer(thresholds: thresholds))
        for frame in frames { pipeline.process(extracted: frame) { nil } }
        return pipeline.reps.count
      }
      print(name.padding(toLength: 40, withPad: " ", startingAt: 0) + want.padding(toLength: 6, withPad: " ", startingAt: 0)
        + counts.map { String(format: "%3d", $0) }.joined(separator: " "))
    }
    print("fixture".padding(toLength: 40, withPad: " ", startingAt: 0) + "want  " + values.map { String(format: "%3.0f", $0) }.joined(separator: " "))
    for fixture in Fixture.all where fixture.expectedExercise == .kettlebellSwing {
      row(fixture.name, "\(fixture.expectedReps)", try fixture.frames())
    }
    let tracks = (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures/tracks") ?? [])
      .filter { $0.lastPathComponent.hasPrefix("kettlebell-swing") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    for url in tracks { row(url.deletingPathExtension().lastPathComponent, "-", try Fixture.frames(at: url)) }
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

extension TuningReports {
  /// Generic-rep experiment (#71, docs/analysis/generic-reps.md): for every known-count fixture and every
  /// archived track, the exercise-blind count beside the known count and the detector's confidence. The number
  /// that decides: how many fixtures land within ±1 of the known count. Prints, never asserts.
  func testGenericRepCounter() throws {
    // An unwired experiment (#71) and the slowest report in the suite: run it on request.
    try XCTSkipUnless(ProcessInfo.processInfo.environment["GENERIC_REPS"] == "1", "set GENERIC_REPS=1 to run the generic-rep report")
    for fixture in Fixture.all {
      let frames = try fixture.frames()
      print(genericLine(label: fixture.name, known: "\(fixture.expectedReps)", frames: frames))
      for interval in GenericRepCounter.count(frames: frames).intervals {
        print(String(format: "    rep %.1f–%.1fs", interval.start, interval.end))
      }
    }
    let urls = (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures/tracks") ?? [])
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
    for url in urls {
      print(genericLine(label: "tracks/" + url.lastPathComponent, known: "—", frames: try Fixture.frames(at: url)))
    }
    print("fixtures: \(Fixture.all.count), archived tracks: \(urls.count)")
  }

  private func genericLine(label: String, known: String, frames: [FrameRecord]) -> String {
    let g = GenericRepCounter.count(frames: frames)
    let d = ExerciseDetector.detect(frames: frames)
    return String(
      format: "%-48@ known %2@ generic %2d  signal %-6@ period %4.1fs r %.2f conf %3d  detector %-22@ %3d%%",
      label as NSString, known as NSString, g.count, (g.signal?.rawValue ?? "none") as NSString,
      g.period, g.periodicity, g.confidence, d.exercise.rawValue as NSString, d.confidence)
  }
}

extension TuningReports {
  /// Held-bell evidence for the kettlebell-detector lab (docs/analysis/kettlebell-detector.md): for every
  /// fixture with sightings, hand frames, detector recall at the hands, tracker hold, and the loss classes,
  /// under the tracker's defaults through AnalysisPipeline.analyze. Prints, never asserts. BELL_LAB_FIXTURES
  /// names a directory of <label>-<clip>.json fixture files to report instead of the repo fixtures.
  func testBellTrackerHeldPerFixture() throws {
    var sources: [(label: String, frames: [FrameRecord], exercise: ExerciseKind)] = []
    if let dir = ProcessInfo.processInfo.environment["BELL_LAB_FIXTURES"], !dir.isEmpty,
      let files = try? FileManager.default.contentsOfDirectory(atPath: dir)
        .filter({ $0.hasSuffix(".json") }).sorted(), !files.isEmpty
    {
      for file in files {
        let url = URL(fileURLWithPath: dir).appendingPathComponent(file)
        let label = (file as NSString).deletingPathExtension
        let exercise: ExerciseKind =
          label.contains("tgu") ? .turkishGetUp
          : label.contains("pistol") ? .pistolSquat
          : label.contains("bulgarian") ? .bulgarianSplitSquat : .kettlebellSwing
        sources.append((label, try Fixture.frames(at: url), exercise))
      }
    } else {
      for (name, exercise) in [
        ("swing-4reps", ExerciseKind.kettlebellSwing), ("swing-1h-9reps", ExerciseKind.kettlebellSwing),
        ("tgu-phone-2min", ExerciseKind.turkishGetUp), ("pistol-6reps", ExerciseKind.pistolSquat),
        ("bulgarian-10reps", ExerciseKind.bulgarianSplitSquat),
      ] as [(String, ExerciseKind)] {
        let fixture = Fixture(name: name, expectedExercise: exercise, expectedReps: 0, humanVerified: false)
        sources.append((name, try fixture.frames(), exercise))
      }
    }
    for source in sources {
      let pipeline = AnalysisPipeline.analyze(frames: source.frames, exercise: source.exercise)
      print(Self.bellHeldLine(
        label: source.label, frames: pipeline.track.frames, zones: pipeline.bellTracker.staticZones,
        reps: pipeline.reps.map { ($0.startTime, $0.endTime) }))
      // BELL_LAB_COLOURS=1: how the held frames vote on the bell's weight (the set's line takes the majority).
      if ProcessInfo.processInfo.environment["BELL_LAB_COLOURS"] == "1" {
        var votes: [String: Int] = [:]
        for f in pipeline.track.frames {
          guard let bell = f.bell else { continue }
          let key = bell.color.map { c in BellColor.weightKg(rgb: c).map { "\($0) kg" } ?? "no code" } ?? "no colour"
          votes[key, default: 0] += 1
        }
        print("COLOURS \(source.label): " + votes.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
      }
      // BELL_LAB_DOTS=1: one line per frame with the reported bell and the wrists, for cutting frames with the
      // dot drawn in so a person (or a vision model) can grade whether it sits on the bell in the hands.
      if ProcessInfo.processInfo.environment["BELL_LAB_DOTS"] == "1" {
        for (i, f) in pipeline.track.frames.enumerated() {
          let wrists = f.pose.map { p in
            [9, 10].compactMap { k -> String? in
              p.conf[k] > BodySkeleton.visibleThreshold ? String(format: "%.3f,%.3f", p.xyn[k].x, p.xyn[k].y) : nil
            }.joined(separator: "/")
          } ?? ""
          let dot = f.bell.map { String(format: "%.3f %.3f %.3f %.3f %.2f", $0.center.x, $0.center.y, $0.box.width, $0.box.height, $0.conf) } ?? "- - - - -"
          print("DOT \(source.label) \(i) \(String(format: "%.3f", f.time)) \(dot) \(wrists.isEmpty ? "-" : wrists)")
        }
      }
    }
  }

  /// One line per fixture: hands-visible frames, detector recall and tracker hold at the hands, then the
  /// loss classes for seen-but-not-held frames (no near-hand sighting at all; every near-hand sighting in
  /// a static zone; track dead with nothing / something startable; track recently alive with nothing in
  /// reach (= blind gap) or something in reach refused (= follow gate)).
  private static func bellHeldLine(label: String, frames: [FrameRecord], zones: Set<Int>, reps: [(Double, Double)]) -> String {
    let startConf = BellTracker.Thresholds().startConf
    var handFrames = 0, seenAtHand = 0, trackedAtHand = 0, heldInZone = 0
    // Inside detected reps the bell is in the hands by definition; outside them it is on the floor for much of a
    // get-up clip (setup, rest, walk-off), so the whole-clip number understates (Codex, 2026-09-13).
    var repHandFrames = 0, repHeld = 0
    var noSight = 0, zone = 0, cold = 0, restartBlocked = 0, dropGap = 0, followRej = 0
    var lastHeld: BellSighting? = nil
    var framesSinceHeld = 9999
    for f in frames {
      guard let pose = f.pose else { continue }
      let wrists = [CocoKeypoint.leftWrist, .rightWrist].compactMap { k -> CGPoint? in
        let i = k.rawValue
        guard i < pose.xyn.count, i < pose.conf.count, pose.conf[i] > BodySkeleton.visibleThreshold else { return nil }
        return CGPoint(x: CGFloat(pose.xyn[i].x), y: CGFloat(pose.xyn[i].y))
      }
      guard !wrists.isEmpty else { continue }
      handFrames += 1
      func nearHand(_ b: BellSighting) -> Bool {
        wrists.contains { hypot($0.x - b.center.x, $0.y - b.center.y) <= 0.2 }
      }
      let near = f.bells.filter(nearHand)
      let held = f.bell.map(nearHand) ?? false
      if reps.contains(where: { f.time >= $0.0 && f.time <= $0.1 }) {
        repHandFrames += 1
        if held { repHeld += 1 }
      }
      if !near.isEmpty { seenAtHand += 1 }
      if held {
        trackedAtHand += 1
        // A held bell sitting in a furniture cell is suspect: the rack behind the hands counts as "near a wrist".
        if let b = f.bell, zones.contains(BellTracker.gridKey(b.center, cell: 0.02)) { heldInZone += 1 }
        lastHeld = f.bell
        framesSinceHeld = 0
        continue
      }
      framesSinceHeld += 1
      guard !near.isEmpty else { noSight += 1; continue }
      let nonZone = near.filter { !zones.contains(BellTracker.gridKey($0.center, cell: 0.02)) }
      guard !nonZone.isEmpty else { zone += 1; continue }
      if framesSinceHeld <= 30, lastHeld != nil {
        // Track recently alive: a non-zone near-hand sighting exists but was not followed.
        dropGap += nonZone.allSatisfy { $0.conf < BellTracker.Thresholds().followConf } ? 1 : 0
        followRej += nonZone.contains { $0.conf >= BellTracker.Thresholds().followConf } ? 1 : 0
        continue
      }
      if nonZone.contains(where: { $0.conf >= startConf }) { restartBlocked += 1 } else { cold += 1 }
    }
    func pct(_ n: Int) -> Int { handFrames > 0 ? 100 * n / handFrames : 0 }
    return
      "bell-held \(label): hands \(handFrames) seen \(pct(seenAtHand))% held \(pct(trackedAtHand))% (inZone \(heldInZone)) inReps \(repHeld)/\(repHandFrames) (\(repHandFrames > 0 ? 100 * repHeld / repHandFrames : 0)%) | noSight=\(noSight) zone=\(zone) cold=\(cold) restartBlocked=\(restartBlocked) dropGap=\(dropGap) followRej=\(followRej)"
  }
}
