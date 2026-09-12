import XCTest
@testable import ExerciseCore
final class SwingThresholdSweep: XCTestCase {
  func testSwingThresholdSweep() throws {
    let names = ["swing-4reps", "swing-1h-9reps", "swing-phone-13reps", "swing-pickup-10reps", "swing-walkin-9reps", "swing-lowcam-10reps"]
    // Tuning report, not an assertion: rep counts across the swing fixtures under alternative thresholds.
    var variants: [(String, SwingThresholds)] = [("defaults", SwingThresholds())]
    var t = SwingThresholds(); t.bottomArmMax = 40; t.topArmMin = 55; variants.append(("strict arms (pre-#16)", t))
    var u = SwingThresholds(); u.topArmMin = 35; variants.append(("topArm 35", u))
    for (label, th) in variants {
      var line = label.padding(toLength: 26, withPad: " ", startingAt: 0)
      for name in names {
        let frames = try Fixture(name: name, expectedExercise: .kettlebellSwing, expectedReps: 0, humanVerified: false).frames()
        let pipeline = AnalysisPipeline(exercise: .kettlebellSwing, analyzer: KettlebellSwingAnalyzer(thresholds: th))
        for f in frames { pipeline.process(extracted: f) { nil } }
        line += " \(name.replacingOccurrences(of: "swing-", with: "")): \(pipeline.reps.count)"
      }
      print(line)
    }
  }
}
