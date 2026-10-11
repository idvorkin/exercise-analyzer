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
      print(
        String(
          format: "%@: %@ %d%%; lunge/all %.3f, lunge/lowered %.3f, wide frames %.0f", fixture.name,
          detection.exercise.rawValue, detection.confidence, detection.stats["lunge_ratio"] ?? 0,
          detection.stats["lunge_low_ratio"] ?? 0, detection.stats["lunge_frames"] ?? 0))
    }
  }

  private func report(_ label: String, _ pipeline: AnalysisPipeline) {
    let lines = pipeline.reps.map { rep -> String in
      let times = rep.positions.values.sorted { $0.time < $1.time }
      let phases = times.map { String(format: "%@ %.1f", $0.phase.prefix(3).description, $0.time) }.joined(
        separator: " ")
      let lost = rep.quality.score < 100 ? "  " + rep.quality.feedback.joined(separator: "; ") : ""
      return String(format: "  #%d %3d  %@%@", rep.number, rep.quality.score, phases, lost)
    }
    print("\(label): \(pipeline.reps.count) reps\n" + lines.joined(separator: "\n"))
  }

  func testBulgarianPhoneSetUnderThresholds() throws {
    let frames = try Fixture(
      name: "bulgarian-phone", expectedExercise: .bulgarianSplitSquat, expectedReps: 0, humanVerified: false
    ).frames()
    let knees = frames.compactMap { $0.pose }.map { pose -> Double in
      let skeleton = BodySkeleton(pose: pose)
      return max(skeleton.kneeAngle(.left), skeleton.kneeAngle(.right))
    }.sorted()
    print(
      String(
        format: "front-ish knee p10 %.0f p50 %.0f p90 %.0f p97 %.0f", knees[knees.count / 10], knees[knees.count / 2],
        knees[knees.count * 9 / 10], knees[knees.count * 97 / 100]))

    var current = BulgarianSplitSquatThresholds()
    report("head-travel defaults", analyze(frames, current))
    current.descendFraction = 0.07
    report("descend at 7% of leg length", analyze(frames, current))
    current.descendFraction = 0.14
    report("descend at 14% of leg length", analyze(frames, current))
  }

  func testBulgarianTenRepSetTrace() throws {
    let frames = try Fixture.named("bulgarian-10reps").frames()
    report("bulgarian-10reps defaults", analyze(frames, BulgarianSplitSquatThresholds()))
  }

  /// #132: Igor's 4CF19A9A set (8 reps, verified) traced, and the two new gates swept over every Bulgarian track:
  /// how deep a dip must go (`minDepthFraction`) and how long the rear foot must be up before a rep may start
  /// (`minSetUpSeconds`).
  func testBulgarianSetupAndWobbleSweep() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "bulgarian-split-squat-20260909-98B26725", withExtension: "json", subdirectory: "Fixtures/tracks"))
    var tracks = try Fixture.all.filter { $0.expectedExercise == .bulgarianSplitSquat }.map {
      ($0.name, try $0.frames())
    }
    tracks.append(("98B26725 (archived, 8)", try Fixture.frames(at: url)))
    let verified = try XCTUnwrap(tracks.first { $0.0 == "bulgarian-4CF19A9A-phone" })
    report("bulgarian-4CF19A9A-phone defaults", analyze(verified.1, BulgarianSplitSquatThresholds()))
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
      tracks.append(
        (
          Fixture(name: name, expectedExercise: .bulgarianSplitSquat, expectedReps: -1, humanVerified: false),
          try Fixture.frames(at: url)
        ))
    }
    func count(_ frames: [FrameRecord], _ t: BulgarianSplitSquatThresholds) -> Int {
      let pipeline = AnalysisPipeline(
        exercise: .bulgarianSplitSquat, analyzer: BulgarianSplitSquatAnalyzer(thresholds: t))
      for frame in frames { pipeline.process(extracted: frame) { nil } }
      return pipeline.reps.count
    }
    let stripped = tracks.map { f, frames in
      (
        f,
        frames.map {
          FrameRecord(
            time: $0.time, imageSize: $0.imageSize, pose: $0.pose, box: $0.box, analysis: nil, bells: $0.bells)
        }
      )
    }
    print(
      "  no bench: "
        + stripped.map {
          "\($0.0.name.prefix(22)) \(count($0.1, BulgarianSplitSquatThresholds()))/\($0.0.expectedReps)"
        }.joined(separator: " · "))
    print(
      "  defaults: "
        + tracks.map { "\($0.0.name.prefix(22)) \(count($0.1, BulgarianSplitSquatThresholds()))/\($0.0.expectedReps)" }
        .joined(separator: " · "))
    for share in [0.15, 0.25, 0.35, 0.5] {
      var t = BulgarianSplitSquatThresholds()
      t.benchTopShare = share
      print(
        String(format: "  top %.2f: ", share)
          + tracks.map { "\($0.0.name.prefix(22)) \(count($0.1, t))/\($0.0.expectedReps)" }.joined(separator: " · "))
    }
    fflush(stdout)  // redirected, XCTest exits with the tail of a long report still buffered
  }

  /// Every Bulgarian fixture's counted bottoms (#172): the knees' side-to-side gap over the standing body height
  /// (ear to lower ankle at Standing), a split stance against a hinge with the feet together (79271425's
  /// put-down: 0.01), then the ankles' gap across and up, the spine's lean and the front knee.
  func testBulgarianBottoms() throws {
    for f in Fixture.all where f.expectedExercise == .bulgarianSplitSquat {
      let reps = AnalysisPipeline.analyze(frames: try f.frames(), exercise: .bulgarianSplitSquat).reps
      let gaps = reps.compactMap { rep -> String? in
        guard let bottom = rep.positions[BulgarianSplitSquatAnalyzer.bottom]?.pose,
          let top = rep.positions[BulgarianSplitSquatAnalyzer.standing]?.pose
        else { return nil }
        let height = Double(max(top.xy[15].y, top.xy[16].y) - min(top.xy[3].y, top.xy[4].y))
        let gap = Double(abs(bottom.xy[13].x - bottom.xy[14].x))
        let ankles = Double(abs(bottom.xy[15].x - bottom.xy[16].x))
        let up = Double(abs(bottom.xy[15].y - bottom.xy[16].y))
        let m = rep.positions[BulgarianSplitSquatAnalyzer.bottom]!.metrics
        // A hinge to the floor: the wrists near the lower ankle, the ear near the hips.
        let s = BodySkeleton(pose: bottom)
        let floor = [s.ankleY(.left), s.ankleY(.right)].compactMap { $0 }.max() ?? 0
        let wrists = [CocoKeypoint.leftWrist, .rightWrist].compactMap { s.point($0).map { Double($0.y) } }.max()
        let hips = [CocoKeypoint.leftHip, .rightHip].compactMap { s.point($0).map { Double($0.y) } }.max()
        let h = max(height, 0.01)
        let wristUp = wrists.map { String(format: "%.2f", (floor - $0) / h) } ?? "-"
        var earOverHip = "-"
        if let hips, let ear = s.earY { earOverHip = String(format: "%.2f", (hips - ear) / h) }
        return String(
          format: "%.1f:%.2f ankles %.2f/%.2f spine %.0f knee %.0f wrist↑%@ ear↑%@",
          rep.positions[BulgarianSplitSquatAnalyzer.bottom]!.time, gap / h, ankles / h, up / h, m["spine"] ?? -1,
          m["frontKnee"] ?? -1, wristUp, earOverHip)
      }
      print(
        "\(f.name), \(reps.count) reps, bottoms (knee gap / height, ankles across/up, spine, front knee):\n  "
          + gaps.joined(separator: "\n  "))
      // Over each rep's whole dip rather than one bottom frame: the spine's median and 90th percentile, the knee
      // gap's median over the standing height, and the share of frames with the knees together (under 0.08).
      let frames = try f.frames()
      for rep in reps {
        guard let top = rep.positions[BulgarianSplitSquatAnalyzer.standing]?.pose else { continue }
        let height = Double(max(top.xy[15].y, top.xy[16].y) - min(top.xy[3].y, top.xy[4].y))
        let dip = frames.filter { $0.time >= rep.startTime && $0.time <= rep.endTime }.compactMap(\.pose)
        let spines = dip.map { BodySkeleton(pose: $0).spineAngle }.sorted()
        let gapsIn = dip.compactMap { p -> Double? in
          guard p.conf[13] > 0.2, p.conf[14] > 0.2 else { return nil }
          return Double(abs(p.xy[13].x - p.xy[14].x)) / max(height, 0.01)
        }.sorted()
        func pct(_ a: [Double], _ q: Double) -> Double {
          a.isEmpty ? -1 : a[min(a.count - 1, Int(Double(a.count) * q))]
        }
        let together = gapsIn.isEmpty ? -1 : Double(gapsIn.filter { $0 < 0.08 }.count) / Double(gapsIn.count)
        print(
          String(
            format: "  rep %d %.1f–%.1f s: spine med %.0f p90 %.0f · knee gap med %.2f · together %.2f", rep.number,
            rep.startTime, rep.endTime, pct(spines, 0.5), pct(spines, 0.9), pct(gapsIn, 0.5), together))
      }
      fflush(stdout)
    }
  }

  /// #135: 79271425's transitions through its setup and first reps (Muse's strips: setup 0.8–4.5 s, reps bottom
  /// at 6.2, 9.4, 13.0, 16.7, 20.2, 23.9, 27.5, 31.8 s, the dumbbells put down at 35.8 s).
  /// 599F988A (Muse's strips: 8 reps, bottoms at 6.1, 9.8, 13.9, 18.1, 22.2, 26.9, 31.2, 36.1 s, then the put-down).
  func testBulgarian79271425Trace() throws {
    for id in ["79271425", "599F988A"] {
      let url = try XCTUnwrap(
        Bundle.module.url(
          forResource: "bulgarian-split-squat-20260922-\(id)", withExtension: "json", subdirectory: "Fixtures/tracks"))
      let analyzer = BulgarianSplitSquatAnalyzer()
      var lines: [String] = []
      analyzer.trace = { lines.append($0) }
      let pipeline = AnalysisPipeline(exercise: .bulgarianSplitSquat, analyzer: analyzer)
      for frame in try Fixture.frames(at: url) { pipeline.process(extracted: frame) { nil } }
      print("\(id):\n" + lines.filter { Double($0.prefix { $0 != "s" }) ?? 99 < 11 }.joined(separator: "\n"))
    }
    fflush(stdout)
  }

  /// The pistol fixtures (#171): where the head goes unmeasured (no ear, no nose) and in which phase, next to each
  /// rep's standing / bottom / done times, so a rule about headless frames is read against the frames it touches.
  func testPistolHeadlessFrames() throws {
    for fixture in Fixture.all where fixture.expectedExercise == .pistolSquat {
      let analyzer = PistolSquatAnalyzer()
      let pipeline = AnalysisPipeline(exercise: .pistolSquat, analyzer: analyzer)
      var runs: [(start: Double, end: Double, phase: String, knee: Double)] = []
      for frame in try fixture.frames() {
        let result = pipeline.process(extracted: frame) { nil }
        guard let pose = frame.pose, BodySkeleton(pose: pose).earY == nil else { continue }
        let phase = result.analysis?.phase ?? "-"
        let knee = BodySkeleton(pose: pose).kneeAngle(.left)
        if let last = runs.last, last.phase == phase, frame.time - last.end < 0.1 {
          runs[runs.count - 1].end = frame.time
        } else {
          runs.append((frame.time, frame.time, phase, knee))
        }
      }
      print("\(fixture.name): \(pipeline.reps.count) reps")
      for rep in pipeline.reps {
        let times = rep.positions.sorted { $0.value.time < $1.value.time }.map {
          String(format: "%@ %.2f", $0.key, $0.value.time)
        }
        print("  rep \(rep.number): " + times.joined(separator: " · ") + String(format: " · done %.2f", rep.endTime))
      }
      for run in runs {
        print(String(format: "  headless %.2f–%.2f s in %@ (left knee %.0f)", run.start, run.end, run.phase, run.knee))
      }
      // Signal by signal, every half second: where the head and the knees come into view, and every dip.
      for frame in try fixture.frames() where Int((frame.time * 30).rounded()) % 15 == 0 {
        guard let pose = frame.pose else { continue }
        let s = BodySkeleton(pose: pose)
        print(
          String(
            format: "  %.2f ear %@ knees L %.0f R %.0f spine %.0f", frame.time,
            s.earY.map { String(format: "%.0f", $0) } ?? "-", s.kneeAngle(.left), s.kneeAngle(.right), s.spineAngle))
      }
    }
    fflush(stdout)
  }

  /// #131: the split-squat fixtures' drawn legs with and without the latch. A jump is a knee or ankle moving more
  /// than 0.05 of the frame between frames; hips are counted apart, to see whether the model trades them too.
  func testLegLatch() throws {
    for fixture in Fixture.all where [.bulgarianSplitSquat, .splitSquat].contains(fixture.expectedExercise) {
      let pipeline = AnalysisPipeline(exercise: fixture.expectedExercise)
      let latch = LegLatch()
      var fixes: [LegLatch.Fix: Int] = [:]
      var raw = (legs: 0, hips: 0, knees: 0)
      var drawn = (legs: 0, knees: 0)
      var lastRaw: Pose?
      var lastDrawn: Pose?
      let legs = [CocoKeypoint.leftKnee, .rightKnee, .leftAnkle, .rightAnkle].map(\.rawValue)
      let knees = [CocoKeypoint.leftKnee, .rightKnee].map(\.rawValue)
      let hips = [CocoKeypoint.leftHip, .rightHip].map(\.rawValue)
      func jumps(_ a: Pose, _ b: Pose, _ ks: [Int]) -> Int {
        ks.filter { a.conf[$0] > 0.2 && b.conf[$0] > 0.2 && LegLatch.distance(a.xyn[$0], b.xyn[$0]) > 0.05 }.count
      }
      var frames = 0
      for frame in try fixture.frames() {
        let result = pipeline.process(extracted: frame) { nil }
        guard let pose = frame.pose else { continue }
        frames += 1
        let standing = result.analysis?.phase == BulgarianSplitSquatAnalyzer.standing
        let (out, fix) = latch.process(pose, standing: standing)
        fixes[fix, default: 0] += 1
        if let lastRaw {
          raw.legs += jumps(lastRaw, pose, legs)
          raw.hips += jumps(lastRaw, pose, hips)
          raw.knees += jumps(lastRaw, pose, knees)
        }
        if let lastDrawn {
          drawn.legs += jumps(lastDrawn, out, legs)
          drawn.knees += jumps(lastDrawn, out, knees)
        }
        lastRaw = pose
        lastDrawn = out
      }
      print(
        "\(fixture.name): \(frames) frames, \(pipeline.reps.count) reps; leg jumps \(raw.legs) → \(drawn.legs), knees \(raw.knees) → \(drawn.knees) (hips \(raw.hips)); "
          + "latched \(fixes[.latched] ?? 0), swapped \(fixes[.swapped] ?? 0), held \(fixes[.held] ?? 0)")
    }
    fflush(stdout)
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
        print(
          String(format: "  minRise %.2f: %d reps", rise, analyzePullUp(frames, thresholds, printing: false).reps.count)
        )
      }
      for under in [0.2, 0.3, 0.4, 0.5, 0.7, 0.9, 1.2] {
        var thresholds = PullUpThresholds()
        thresholds.letGoUnderBar = under
        print(
          String(
            format: "  letGoUnderBar %.2f: %d reps", under,
            analyzePullUp(frames, thresholds, printing: false).reps.count))
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
        print(
          String(
            format: "  minDepth %.2f: %d reps", depth, analyzeSplitSquat(frames, thresholds, printing: false).reps.count
          ))
      }
      for split in [0.0, 0.3, 0.6, 1.0, 1.4, 1.8] {
        var thresholds = SplitSquatThresholds()
        thresholds.minSplit = split
        print(
          String(
            format: "  minSplit %.2f: %d reps", split, analyzeSplitSquat(frames, thresholds, printing: false).reps.count
          ))
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
      print(
        String(
          format: "rep %d standing %.2f s hips %.4f bottom %.2f s", rep.number, top.time, stance.hipHeight,
          rep.positions["bottom"]!.time))
    }
  }

  private func analyzeSplitSquat(
    _ frames: [FrameRecord], _ thresholds: SplitSquatThresholds, printing: Bool
  ) -> AnalysisPipeline {
    let analyzer = SplitSquatAnalyzer(thresholds: thresholds)
    var transitions: [String] = []
    analyzer.trace = { transitions.append($0) }
    let pipeline = AnalysisPipeline(exercise: .splitSquat, analyzer: analyzer)
    for frame in frames { pipeline.process(extracted: frame) { nil } }
    if printing { print(transitions.map { "    " + $0 }.joined(separator: "\n")) }
    return pipeline
  }

  private func analyzePullUp(
    _ frames: [FrameRecord], _ thresholds: PullUpThresholds, printing: Bool
  ) -> AnalysisPipeline {
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
        lines.append(
          String(
            format:
              "  #%2d top %5.2f con %5.2f bot %5.2f rel %5.2f done %5.2f  span %4.2f  hinge %3.0f lock %3.0f kneeFlex %3.0f  topArm %3.0f topWrist %5.0f",
            rep.number, p["top"]?.time ?? 0, p["connect"]?.time ?? 0, p["bottom"]?.time ?? 0, p["release"]?.time ?? 0,
            done,
            done - (p["top"]?.time ?? 0), q["hingeDepth"] ?? 0, q["lockoutAngle"] ?? 0, q["kneeFlexion"] ?? 0,
            p["top"]?.metrics["arm"] ?? 0, p["top"]?.metrics["wristHeight"] ?? 0))
      }
      print("\(fixture.name): \(pipeline.reps.count) reps\n" + lines.joined(separator: "\n"))
    }
  }

  /// Every frame's swing signals and phase for one archived track, between two times:
  /// `SWING_TRACK=kettlebell-swing-20260918-5C13D496 SWING_FROM=12 SWING_TO=17 swift test --filter testSwingSignals`.
  /// A fixture name (`SWING_TRACK=swing-walkin-9reps`) works too.
  func testSwingSignals() throws {
    let env = ProcessInfo.processInfo.environment
    guard let name = env["SWING_TRACK"] else {
      throw XCTSkip("set SWING_TRACK=<fixture or archived track> to print a swing's signals")
    }
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/tracks")
        ?? Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
      "missing track \(name)")
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
      print(
        String(
          format: "  %6.2f  %-8@ rep %2d  arm %4.0f spine %4.0f hip %4.0f knee %4.0f wrist %5.0f%@",
          frame.time, a.phase, a.repCount, m["arm"] ?? 0, m["spine"] ?? 0, m["hip"] ?? 0, m["knee"] ?? 0,
          m["wristHeight"] ?? 0,
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
    let topHip = Double(env["SWING_TOP_HIP"] ?? "")
    let maxRep = Double(env["SWING_MAX_REP"] ?? "")
    let ballistic = Double(env["SWING_BALLISTIC"] ?? "")
    let values = [40.0, 38, 36, 34, 32, 30, 28]
    func row(_ name: String, _ want: String, _ frames: [FrameRecord]) {
      let counts = values.map { value -> Int in
        var thresholds = SwingThresholds()
        thresholds.ballisticTopArmMin = value
        if let topHip { thresholds.topHipMin = topHip }
        if let maxRep { thresholds.maxRepDuration = maxRep }
        if let ballistic { thresholds.ballisticReleaseMax = ballistic }
        let pipeline = AnalysisPipeline(
          exercise: .kettlebellSwing, analyzer: KettlebellSwingAnalyzer(thresholds: thresholds))
        for frame in frames { pipeline.process(extracted: frame) { nil } }
        return pipeline.reps.count
      }
      print(
        name.padding(toLength: 40, withPad: " ", startingAt: 0) + want.padding(toLength: 6, withPad: " ", startingAt: 0)
          + counts.map { String(format: "%3d", $0) }.joined(separator: " "))
    }
    print(
      "fixture".padding(toLength: 40, withPad: " ", startingAt: 0) + "want  "
        + values.map { String(format: "%3.0f", $0) }.joined(separator: " "))
    for fixture in Fixture.all where fixture.expectedExercise == .kettlebellSwing {
      row(fixture.name, "\(fixture.expectedReps)", try fixture.frames())
    }
    let tracks = (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures/tracks") ?? [])
      .filter { $0.lastPathComponent.hasPrefix("kettlebell-swing") }.sorted {
        $0.lastPathComponent < $1.lastPathComponent
      }
    for url in tracks { row(url.deletingPathExtension().lastPathComponent, "-", try Fixture.frames(at: url)) }
  }

  /// #139: a far camera behind the lifter reads the float at 30–38°. Counts every swing fixture and archived
  /// track with the wrist-rise top rule off ("off") and at each `wristTopRiseMin` (torso lengths);
  /// SWING_WRIST_ARM overrides `wristTopArmMin`.
  func testSwingWristRiseSweep() throws {
    let armFloor = Double(ProcessInfo.processInfo.environment["SWING_WRIST_ARM"] ?? "")
    let values: [Double?] = [nil, -0.7, -0.6, -0.5, -0.4, -0.3]
    func row(_ name: String, _ want: String, _ frames: [FrameRecord]) {
      let counts = values.map { value -> Int in
        var thresholds = SwingThresholds()
        thresholds.wristTopRiseMin = value
        if let armFloor { thresholds.wristTopArmMin = armFloor }
        let pipeline = AnalysisPipeline(
          exercise: .kettlebellSwing, analyzer: KettlebellSwingAnalyzer(thresholds: thresholds))
        for frame in frames { pipeline.process(extracted: frame) { nil } }
        return pipeline.reps.count
      }
      let marks = counts.dropFirst().contains { $0 != counts[0] } ? "  *" : ""
      print(
        name.padding(toLength: 40, withPad: " ", startingAt: 0) + want.padding(toLength: 6, withPad: " ", startingAt: 0)
          + counts.map { String(format: "%4d", $0) }.joined(separator: " ") + marks)
    }
    print(
      "fixture".padding(toLength: 40, withPad: " ", startingAt: 0) + "want  "
        + values.map { $0.map { String(format: "%4.1f", $0) } ?? " off" }.joined(separator: " "))
    for fixture in Fixture.all where fixture.expectedExercise == .kettlebellSwing {
      row(fixture.name, "\(fixture.expectedReps)", try fixture.frames())
    }
    let tracks = (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures/tracks") ?? [])
      .filter { $0.lastPathComponent.hasPrefix("kettlebell-swing") }.sorted {
        $0.lastPathComponent < $1.lastPathComponent
      }
    for url in tracks { row(url.deletingPathExtension().lastPathComponent, "-", try Fixture.frames(at: url)) }
  }

  /// #148: the first swing counts. Every swing fixture's and archived track's count with the hike rule off
  /// ("off", every rep over `maxRepDuration` discarded) and at each `hikeReleaseMax`, then, for every set the
  /// default changes, each rep it adds: where it sits (its number of the total, bottom, release, top) and the angles
  /// that make it a swing (the hinge at the bottom, the hip at the snap, the arm at the top). A rep added at
  /// the end of a set would be a bell park.
  func testSwingHikeSweep() throws {
    let values: [Double?] = [nil, 0.3, 0.4, 0.6, 1.0]
    struct Rep { let bottom: RepPosition?, release: RepPosition?, top: FrameRecord }
    func run(_ frames: [FrameRecord], _ value: Double?) -> [Rep] {
      var thresholds = SwingThresholds()
      thresholds.hikeReleaseMax = value
      thresholds.slowTopConfirmGap = nil  // a hike's rep completes at its top, not at the hinge that confirms it (#149)
      let pipeline = AnalysisPipeline(
        exercise: .kettlebellSwing, analyzer: KettlebellSwingAnalyzer(thresholds: thresholds))
      for frame in frames { pipeline.process(extracted: frame) { nil } }
      let tops = pipeline.track.frames.filter { $0.analysis?.completedRep != nil }
      return zip(pipeline.reps, tops).map {
        Rep(bottom: $0.positions["bottom"], release: $0.positions["release"], top: $1)
      }
    }
    var added: [String] = []
    func row(_ name: String, _ want: String, _ frames: [FrameRecord]) {
      let counts = values.map { run(frames, $0).count }
      let marks = counts.dropFirst().contains { $0 != counts[0] } ? "  *" : ""
      print(
        name.padding(toLength: 40, withPad: " ", startingAt: 0) + want.padding(toLength: 6, withPad: " ", startingAt: 0)
          + counts.map { String(format: "%4d", $0) }.joined(separator: " ") + marks)
      let before = run(frames, nil)
      let after = run(frames, SwingThresholds().hikeReleaseMax)
      for (i, rep) in after.enumerated() where !before.contains(where: { abs($0.top.time - rep.top.time) < 0.05 }) {
        let b = rep.bottom?.metrics ?? [:]
        let r = rep.release?.metrics ?? [:]
        let t = rep.top.analysis?.metrics ?? [:]
        // The float: the highest the wrists get in the half second after the top (torso lengths; about -1 hanging).
        let float =
          frames.filter { $0.time >= rep.top.time && $0.time <= rep.top.time + 0.5 }
          .compactMap { $0.pose.flatMap { BodySkeleton(pose: $0).wristRise } }.max() ?? -9
        added.append(
          String(
            format:
              "  %@ rep %d/%d: bottom %5.2f (spine %2.0f hip %3.0f) release %5.2f (hip %3.0f) top %5.2f (arm %2.0f hip %3.0f, %.2f s after release) float %5.2f",
            name, i + 1, after.count, rep.bottom?.time ?? -1, b["spine"] ?? 0, b["hip"] ?? 0, rep.release?.time ?? -1,
            r["hip"] ?? 0,
            rep.top.time, t["arm"] ?? 0, t["hip"] ?? 0, rep.top.time - (rep.release?.time ?? 0), float))
      }
    }
    print(
      "fixture".padding(toLength: 40, withPad: " ", startingAt: 0) + "want  "
        + values.map { $0.map { String(format: "%4.1f", $0) } ?? " off" }.joined(separator: " "))
    for fixture in Fixture.all where fixture.expectedExercise == .kettlebellSwing {
      row(fixture.name, "\(fixture.expectedReps)", try fixture.frames())
    }
    let tracks = (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures/tracks") ?? [])
      .filter { $0.lastPathComponent.hasPrefix("kettlebell-swing") }.sorted {
        $0.lastPathComponent < $1.lastPathComponent
      }
    for url in tracks { row(url.deletingPathExtension().lastPathComponent, "-", try Fixture.frames(at: url)) }
    print("reps the default adds:\n" + added.joined(separator: "\n"))
  }

  /// Raw signals for a fixture at ~4 Hz, plus a naive rep count from smoothed knee-angle dips.
  func testBulgarianPhoneSignals() throws {
    let frames = try Fixture(
      name: "bulgarian-phone", expectedExercise: .bulgarianSplitSquat, expectedReps: 0, humanVerified: false
    ).frames()
    var lines: [String] = []
    var minKnee: [Double] = []
    for frame in frames {
      guard let pose = frame.pose else {
        minKnee.append(180)
        continue
      }
      let s = BodySkeleton(pose: pose)
      let l = s.kneeAngle(.left)
      let r = s.kneeAngle(.right)
      minKnee.append(min(l > 0 ? l : 180, r > 0 ? r : 180))
      let la = s.ankleY(.left) ?? 0
      let ra = s.ankleY(.right) ?? 0
      if Int(frame.time * 4) != Int((frame.time - 1.0 / 30) * 4) {
        lines.append(
          String(
            format:
              "%5.1fs  kneeL %3.0f kneeR %3.0f  spine %2.0f  ear %4.0f  ankleL %4.0f ankleR %4.0f  conf L%.1f R%.1f",
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
    var dips = 0
    var below = false
    for v in smoothed {
      if !below && v < 110 {
        below = true
        dips += 1
      }
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
        if let sh = s.point(.leftShoulder) ?? s.point(.rightShoulder), let hip = s.point(.leftHip) ?? s.point(.rightHip)
        {
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
    let v1 = CGVector(dx: a.x - v.x, dy: a.y - v.y)
    let v2 = CGVector(dx: b.x - v.x, dy: b.y - v.y)
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
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["GENERIC_REPS"] == "1", "set GENERIC_REPS=1 to run the generic-rep report")
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
          label.contains("tgu")
          ? .turkishGetUp
          : label.contains("pistol")
            ? .pistolSquat
            : label.contains("bulgarian") ? .bulgarianSplitSquat : .kettlebellSwing
        sources.append((label, try Fixture.frames(at: url), exercise))
      }
    } else {
      for (name, exercise) in [
        ("swing-4reps", ExerciseKind.kettlebellSwing), ("swing-1h-10reps", ExerciseKind.kettlebellSwing),
        ("tgu-phone-2min", ExerciseKind.turkishGetUp), ("pistol-5reps", ExerciseKind.pistolSquat),
        ("bulgarian-10reps", ExerciseKind.bulgarianSplitSquat),
      ] as [(String, ExerciseKind)] {
        let fixture = Fixture(name: name, expectedExercise: exercise, expectedReps: 0, humanVerified: false)
        sources.append((name, try fixture.frames(), exercise))
      }
    }
    for source in sources {
      let pipeline = AnalysisPipeline.analyze(frames: source.frames, exercise: source.exercise)
      print(
        Self.bellHeldLine(
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
        print(
          "COLOURS \(source.label): "
            + votes.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
      }
      // BELL_LAB_DOTS=1: one line per frame with the reported bell and the wrists, for cutting frames with the
      // dot drawn in so a person (or a vision model) can grade whether it sits on the bell in the hands.
      if ProcessInfo.processInfo.environment["BELL_LAB_DOTS"] == "1" {
        for (i, f) in pipeline.track.frames.enumerated() {
          let wrists =
            f.pose.map { p in
              [9, 10].compactMap { k -> String? in
                p.conf[k] > BodySkeleton.visibleThreshold ? String(format: "%.3f,%.3f", p.xyn[k].x, p.xyn[k].y) : nil
              }.joined(separator: "/")
            } ?? ""
          let dot =
            f.bell.map {
              String(format: "%.3f %.3f %.3f %.3f %.2f", $0.center.x, $0.center.y, $0.box.width, $0.box.height, $0.conf)
            } ?? "- - - - -"
          print("DOT \(source.label) \(i) \(String(format: "%.3f", f.time)) \(dot) \(wrists.isEmpty ? "-" : wrists)")
        }
      }
    }
  }

  /// One line per fixture: hands-visible frames, detector recall and tracker hold at the hands, then the
  /// loss classes for seen-but-not-held frames (no near-hand sighting at all; every near-hand sighting in
  /// a static zone; track dead with nothing / something startable; track recently alive with nothing in
  /// reach (= blind gap) or something in reach refused (= follow gate)).
  private static func bellHeldLine(
    label: String, frames: [FrameRecord], zones: Set<Int>, reps: [(Double, Double)]
  ) -> String {
    let startConf = BellTracker.Thresholds().startConf
    var handFrames = 0
    var seenAtHand = 0
    var trackedAtHand = 0
    var heldInZone = 0
    // Inside detected reps the bell is in the hands by definition; outside them it is on the floor for much of a
    // get-up clip (setup, rest, walk-off), so the whole-clip number understates (Codex, 2026-09-13).
    var repHandFrames = 0
    var repHeld = 0
    var noSight = 0
    var zone = 0
    var cold = 0
    var restartBlocked = 0
    var dropGap = 0
    var followRej = 0
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
      guard !near.isEmpty else {
        noSight += 1
        continue
      }
      let nonZone = near.filter { !zones.contains(BellTracker.gridKey($0.center, cell: 0.02)) }
      guard !nonZone.isEmpty else {
        zone += 1
        continue
      }
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

extension TuningReports {
  /// Off-angle top brainstorm (#139, #149; lab note ~/tmp/agent/notes/2026-09-26-offangle-top-brainstorm.md): a
  /// swing's top is reached within a second of the deepest frame of its hinge (every fixture and archived rep:
  /// p99 0.80 s, max 0.93 s); a top that took longer is either the hike off the floor (a hinge follows within
  /// 1.0–1.3 s) or the lifter standing up after parking the bell (nothing follows for 6 s or more). For every
  /// swing fixture and archived track, each rep's deepest-hinge→top and release→top times, the arm at the top, and
  /// the time to the next hinge (spine > 35, hip < 140); the "two-speed" column counts a slow top only when a
  /// hinge follows within `SWING_NEXT_HINGE` s (default 2.5), `SWING_UPSWING` (default 1.0) sets what is slow.
  /// Reads the analyzer with the rule off (`slowTopConfirmGap` nil, "off"); "2spd" is the rule as a post-filter
  /// on that output, "rule" the analyzer's own count with `upswingMaxDuration` and `slowTopConfirmGap` set to the
  /// same values (#149; `!` marks a set where the two disagree).
  func testSwingUpswingReport() throws {
    let env = ProcessInfo.processInfo.environment
    let upswingMax = Double(env["SWING_UPSWING"] ?? "") ?? 1.0
    let nextHingeMax = Double(env["SWING_NEXT_HINGE"] ?? "") ?? 2.5
    var slowLines: [String] = []
    func run(_ frames: [FrameRecord], gap: Double?) -> AnalysisPipeline {
      var thresholds = SwingThresholds()
      thresholds.upswingMaxDuration = upswingMax
      thresholds.slowTopConfirmGap = gap
      let pipeline = AnalysisPipeline(
        exercise: .kettlebellSwing, analyzer: KettlebellSwingAnalyzer(thresholds: thresholds))
      for frame in frames { pipeline.process(extracted: frame) { nil } }
      return pipeline
    }
    func row(_ name: String, _ want: String, _ frames: [FrameRecord]) {
      let pipeline = run(frames, gap: nil)
      let rule = run(frames, gap: nextHingeMax).reps.count
      let track = pipeline.track.frames
      let tops = track.filter { $0.analysis?.completedRep != nil }
      var kept = 0
      for (rep, top) in zip(pipeline.reps, tops) {
        let bottom = rep.positions["bottom"]?.time ?? -1
        let upswing = top.time - bottom
        let release = top.time - (rep.positions["release"]?.time ?? top.time)
        let nextHinge = track.first { f in
          guard f.time > top.time, let m = f.analysis?.metrics, let spine = m["spine"], let hip = m["hip"] else {
            return false
          }
          return spine > 35 && hip < 140
        }.map { $0.time - top.time }
        let slow = bottom < 0 || upswing > upswingMax
        let confirmed = nextHinge.map { $0 <= nextHingeMax } ?? false
        if !slow || confirmed { kept += 1 }
        if slow {
          slowLines.append(
            String(
              format:
                "  %@ rep %d/%d at %5.2f: deepest->top %.2f s, release->top %.2f s, arm %2.0f, next hinge %@ -> %@",
              name, rep.number, pipeline.reps.count, top.time, upswing, release, top.analysis?.metrics["arm"] ?? 0,
              nextHinge.map { String(format: "%.2f s", $0) } ?? "none", confirmed ? "hike, counted" : "park, dropped"))
        }
      }
      print(
        name.padding(toLength: 40, withPad: " ", startingAt: 0) + want.padding(toLength: 6, withPad: " ", startingAt: 0)
          + String(
            format: "%4d %4d %4d%@%@", pipeline.reps.count, kept, rule, kept != pipeline.reps.count ? "  *" : "",
            rule != kept ? "  !" : ""))
    }
    print("fixture".padding(toLength: 40, withPad: " ", startingAt: 0) + "want   off 2spd rule")
    for fixture in Fixture.all where fixture.expectedExercise == .kettlebellSwing {
      row(fixture.name, "\(fixture.expectedReps)", try fixture.frames())
    }
    let tracks = (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures/tracks") ?? [])
      .filter { $0.lastPathComponent.hasPrefix("kettlebell-swing") }.sorted {
        $0.lastPathComponent < $1.lastPathComponent
      }
    for url in tracks { row(url.deletingPathExtension().lastPathComponent, "-", try Fixture.frames(at: url)) }
    print("slow tops (deepest hinge -> top over \(upswingMax) s):\n" + slowLines.joined(separator: "\n"))
  }
}
