// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 083 (#377): a barbell set's weight as plates per side on a chosen bar, added up by the app; one weight per
//  set, a bell or a barbell, carried, counted in the load and merged across devices like a bell's (066, 070).

import XCTest

@testable import ExerciseCore

final class BarbellTests: XCTestCase {
  private let me = "ipad"
  private let phone = "phone"

  private func set(
    _ id: String, _ kind: ExerciseKind = .splitSquat, reps: Int = 10, at: Double, weight: SetWeight? = nil
  ) -> RecentEntry {
    var entry = RecentEntry(
      id: id, analyzedAt: Date(timeIntervalSince1970: at + 40), recordedAt: nil, duration: 30, repCount: reps,
      bestScore: 80, source: .file(name: "clip.mov"), thumbnail: nil, exercise: kind, originalName: nil,
      clipStartedAt: Date(timeIntervalSince1970: at))
    if let weight { entry.setWeight(weight, by: me, at: Date(timeIntervalSince1970: at + 50)) }
    return entry
  }

  private var ssb45: BarbellLoad { BarbellLoad(bar: .safetySquat, plates: [45]) }

  func testFortyFivePerSideOnTheSafetySquatBarIs148() {
    XCTAssertEqual(BarKind.safetySquat.lb, 58)
    XCTAssertEqual(BarKind.regular.lb, 45)
    XCTAssertEqual(ssb45.perSideLb, 45)
    XCTAssertEqual(ssb45.totalLb, 148)
    XCTAssertEqual(ssb45.kg, 67, "148 lb is 67.1 kg")
    XCTAssertEqual(SetWeight.barbell(ssb45).label, "148 lb")
    XCTAssertEqual(ssb45.sideLabel, "45/side")
    XCTAssertEqual(SetWeight.barbell(ssb45).spoken, "148 pounds, safety squat bar, 45 per side")
    XCTAssertEqual(SetWeight.bell(24).label, "24 kg")
    XCTAssertEqual(SetWeight.bell(24).kg, 24)
  }

  func testPlatesAddAndComeOffOneAtATimeHeaviestFirst() {
    var load = BarbellLoad(bar: .regular)
    XCTAssertEqual(load.totalLb, 45, "an empty bar")
    XCTAssertEqual(load.sideLabel, "empty bar")
    load.add(10)
    load.add(45)
    load.add(10)
    XCTAssertEqual(load.count(of: 10), 2)
    XCTAssertEqual(load.perSideLb, 65)
    XCTAssertEqual(load.totalLb, 45 + 130)
    XCTAssertEqual(load.sideLabel, "45+10+10/side")
    load.remove(10)
    load.remove(10)
    load.remove(10)
    XCTAssertEqual(load.count(of: 10), 0, "never below none")
    XCTAssertEqual(load.plates, [45])
    load.add(5)
    XCTAssertEqual(load.perSideLb, 45, "only the gym's plates")
    XCTAssertEqual(
      BarbellLoad(bar: .regular, plates: [10, 45, 25]), BarbellLoad(bar: .regular, plates: [45, 25, 10]),
      "the same plates in any order are the same load")
  }

  /// #387: Igor tapped his way to 45 ×15 a side (1,448 lb). A side takes at most 8 plates; more taps do nothing.
  func testASideHoldsAtMostEightPlates() {
    var load = BarbellLoad(bar: .safetySquat)
    for _ in 0..<15 { load.add(45) }
    XCTAssertEqual(load.count(of: 45), BarbellLoad.maxPlatesPerSide)
    XCTAssertEqual(BarbellLoad.maxPlatesPerSide, 8)
    XCTAssertTrue(load.isFull)
    load.add(10)
    XCTAssertEqual(load.count(of: 10), 0, "a full side takes no smaller plate either")
    XCTAssertEqual(load.totalLb, 58 + 2 * 8 * 45)
    load.remove(45)
    XCTAssertFalse(load.isFull)
    load.add(10)
    XCTAssertEqual(load.plates.count, 8)
  }

  /// "Empty bar" takes every plate off; the bar stays.
  func testEmptyingTheBarKeepsTheBar() {
    var load = BarbellLoad(bar: .sixtyFive, plates: [45, 25, 10])
    load.empty()
    XCTAssertEqual(load, BarbellLoad(bar: .sixtyFive))
    XCTAssertEqual(load.totalLb, 65)
  }

  /// The cap is on adding only: a load stored or synced with more plates (an older build) is shown as it is.
  func testAStoredLoadOverTheCapIsKept() throws {
    let fifteen = Array(repeating: 45, count: 15)
    XCTAssertEqual(BarbellLoad(bar: .safetySquat, plates: fifteen).plates.count, 15)
    let json = Data(#"{"bar":"safety-squat","plates":\#(fifteen)}"#.utf8)
    let decoded = try JSONDecoder().decode(BarbellLoad.self, from: json)
    XCTAssertEqual(decoded.totalLb, 58 + 2 * 15 * 45)
    XCTAssertTrue(decoded.isFull)
  }

  func testOneWeightPerSetTheLaterReplacingTheOther() {
    var entry = set("a", at: 100, weight: .bell(24))
    entry.setWeight(.barbell(ssb45), by: me, at: Date(timeIntervalSince1970: 300))
    XCTAssertNil(entry.bellKg)
    XCTAssertEqual(entry.weight, .barbell(ssb45))
    XCTAssertEqual(entry.bellKgEditedAt, Date(timeIntervalSince1970: 300), "one edit time for the set's weight")
    entry.setBellKg(20, by: me, at: Date(timeIntervalSince1970: 400))
    XCTAssertNil(entry.barbell)
    XCTAssertEqual(entry.weight, .bell(20))
    entry.setWeight(nil, by: me, at: Date(timeIntervalSince1970: 500))
    XCTAssertNil(entry.weight)
  }

  func testARowFromBeforeBarbellsStillReads() throws {
    let old = set("a", at: 100, weight: .bell(24))
    let data = try JSONEncoder().encode(old)
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))
    XCTAssertFalse(json.contains("barbell"), "no key written for a set without plates")
    let read = try JSONDecoder().decode(RecentEntry.self, from: data)
    XCTAssertEqual(read.weight, .bell(24))
    let withPlates = set("b", at: 100, weight: .barbell(ssb45))
    let back = try JSONDecoder().decode(RecentEntry.self, from: JSONEncoder().encode(withPlates))
    XCTAssertEqual(back.weight, .barbell(ssb45))
  }

  func testTheWorkoutPageCarriesThePlatesAndCountsThemInKg() {
    let workout = StoredWorkout(
      id: "w", start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3600), heartRateAverage: nil,
      heartRateMax: nil, sets: 4, reps: 40)
    let timeline = WorkoutTimeline(
      workout: workout,
      sets: [
        set("l1", at: 100, weight: .barbell(ssb45)), set("l2", at: 300),
        set("s1", .kettlebellSwing, at: 500, weight: .bell(24)), set("l3", at: 700),
      ],
      heartRate: nil)
    XCTAssertEqual(timeline.rows.map(\.weight), [.barbell(ssb45), .barbell(ssb45), .bell(24), .barbell(ssb45)])
    XCTAssertEqual(timeline.rows.map(\.kgInherited), [false, true, false, true])
    XCTAssertEqual(timeline.rows.map(\.kg), [67, 67, 24, 67])
    XCTAssertEqual(timeline.loadKg, 3 * 10 * 67 + 10 * 24)
  }

  func testTheProgressionCountsThePlatesInKg() {
    let weeks = ProgressionSeries.weeks(
      of: .splitSquat, sets: [set("l1", at: 100, weight: .barbell(ssb45)), set("l2", at: 300)], workouts: [])
    XCTAssertEqual(weeks.first?.loadKg, 2 * 10 * 67)
    XCTAssertEqual(weeks.first?.heaviestKg, 67)
  }

  func testTheByHandPickersOpenOnTheExercisesLastWeightPlatesIncluded() {
    let entries = [
      set("new", at: 300, weight: .barbell(ssb45)), set("old", at: 100, weight: .bell(24)),
      set("kb", .kettlebellSwing, at: 200, weight: .bell(16)),
    ]
    XCTAssertEqual(RecentEntry.lastWeight(entries), [.splitSquat: .barbell(ssb45), .kettlebellSwing: .bell(16)])
    XCTAssertEqual(RecentEntry.lastBellKg(entries), [.splitSquat: 24, .kettlebellSwing: 16], "the wrist's bells")
  }

  func testASetTypedByHandKeepsItsPlates() {
    let typed = HandSet(exercise: .splitSquat, reps: 8, at: 100, barbell: ssb45)
    XCTAssertEqual(typed.entry.weight, .barbell(ssb45))
    let fromWrist = HandSet(exercise: .splitSquat, reps: 8, at: 100, kg: 24)
    XCTAssertEqual(fromWrist.entry.weight, .bell(24))
    let kept = set("a", at: 100, weight: .barbell(ssb45)).keptByHand(exercise: .splitSquat, reps: 9)
    XCTAssertEqual(kept.weight, .barbell(ssb45), "the lifter's plates are not the camera's")
  }

  func testPlatesTypedHereSurviveAReanalysisThere() throws {
    let weighed = set("a", at: 100, weight: .barbell(ssb45))
    var reanalysis = set("a", reps: 11, at: 100)
    reanalysis.refreshed(by: phone, at: Date(timeIntervalSince1970: 1_000))
    let merged = try XCTUnwrap(weighed.merged(remote: reanalysis, me: me))
    XCTAssertEqual(merged.repCount, 11)
    XCTAssertEqual(merged.weight, .barbell(ssb45))
  }

  func testPlatesTypedThereReachThisDevice() throws {
    let mine = set("a", at: 100, weight: .bell(24))
    var theirs = mine
    theirs.setWeight(.barbell(ssb45), by: phone, at: Date(timeIntervalSince1970: 1_000))
    let merged = try XCTUnwrap(mine.merged(remote: theirs, me: me))
    XCTAssertEqual(merged.weight, .barbell(ssb45))
    XCTAssertNil(merged.bellKg)
  }

  func testAnOlderBuildRewritingTheSetDoesNotEraseThePlates() throws {
    // The other device's build does not know `barbell`: its re-analysis rewrites the row with the same weight edit
    // time and no plates.
    let mine = set("a", at: 100, weight: .barbell(ssb45))
    var theirs = mine
    theirs.barbell = nil
    theirs.repCount = 11
    theirs.refreshed(by: phone, at: Date(timeIntervalSince1970: 1_000))
    let merged = try XCTUnwrap(mine.merged(remote: theirs, me: me))
    XCTAssertEqual(merged.repCount, 11)
    XCTAssertEqual(merged.weight, .barbell(ssb45))
  }

  /// #388: reverse lunges, logged as split squats, are loaded on a bar; the weight row offers the bar, not bells.
  func testOnlySplitSquatsTakeABar() {
    XCTAssertEqual(ExerciseKind.allCases.filter(\.takesBar), [.splitSquat])
  }

  /// #380: the by-hand sheet's inline picker shows the kind of the exercise's last weight, the set's own first,
  /// then its last in any workout, then its starting weight (066), then plates only for an exercise on a bar.
  func testTheInlinePickerShowsTheKindOfTheLastWeight() {
    let swing = ExerciseKind.kettlebellSwing
    XCTAssertFalse(swing.picksPlates(own: nil, last: nil), "swings start on a bell")
    XCTAssertTrue(ExerciseKind.splitSquat.picksPlates(own: nil, last: nil), "lunges start on the safety squat bar")
    XCTAssertFalse(ExerciseKind.pullUp.picksPlates(own: nil, last: nil), "no start, no bar: the bells")
    XCTAssertTrue(swing.picksPlates(own: nil, last: .barbell(ssb45)), "the last swing set was plates")
    XCTAssertFalse(ExerciseKind.splitSquat.picksPlates(own: nil, last: .bell(16)), "the last lunge set was a bell")
    XCTAssertTrue(swing.picksPlates(own: .barbell(ssb45), last: .bell(24)), "the set's own weight first")
    XCTAssertFalse(ExerciseKind.splitSquat.picksPlates(own: .bell(16), last: .barbell(ssb45)), "a bell is kept")
  }

  /// #380: what the inline plates open on with no plates on the set: the exercise's last plates, else its starting
  /// plates, else a 45 a side on the barbell.
  func testTheInlinePlatesOpenOnTheLastThenTheStartingPlates() {
    let ssb10 = BarbellLoad(bar: .safetySquat, plates: [10])
    XCTAssertEqual(ExerciseKind.splitSquat.platesStart(own: nil, last: nil), ssb10)
    XCTAssertEqual(ExerciseKind.splitSquat.platesStart(own: nil, last: .barbell(ssb45)), ssb45)
    XCTAssertEqual(ExerciseKind.splitSquat.platesStart(own: .barbell(ssb45), last: nil), ssb45)
    XCTAssertEqual(ExerciseKind.kettlebellSwing.platesStart(own: .bell(24), last: .bell(24)), .start)
  }

  /// The drawing of the loaded bar (#388): heaviest nearest the middle, each plate as tall as it is heavy.
  func testTheDrawnBarStacksHeaviestInsideAndSizesByWeight() {
    let load = BarbellLoad(bar: .safetySquat, plates: [10, 45, 25, 45])
    XCTAssertEqual(load.plates, [45, 45, 25, 10], "inside out, as they are loaded")
    let heights = BarbellLoad.plateSizes.map(BarbellLoad.drawnHeight)
    XCTAssertEqual(heights, heights.sorted(by: >), "a heavier plate is never drawn shorter")
    XCTAssertEqual(BarbellLoad.drawnHeight(45), 1)
    XCTAssertGreaterThan(BarbellLoad.drawnHeight(10), 0.3, "the 10 still reads as a plate")
  }
}
