// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 059 (#136): a set typed on the wrist. The count page's start and range, the wire to the phone, and the
//  phone's "by hand" entry: one per id, counted in the workout, never re-read, removed without a video.

import Foundation
import XCTest

@testable import ExerciseCore

final class HandSetTests: XCTestCase {
  private let swing = ExerciseKind.kettlebellSwing
  private let getUp = ExerciseKind.turkishGetUp

  /// #158: sit-ups and half-kneeling rotations are typed by hand only; nothing points the camera's analysis at them.
  func testCountOnlyExercisesTravelByHandButNeverSetTheAnalysisMode() throws {
    for kind in [ExerciseKind.sitUp, .halfKneelingRotation] {
      XCTAssertTrue(kind.countOnly)
      XCTAssertFalse(ExerciseKind.analyzable.contains(kind))
      XCTAssertEqual(ExerciseMode(storageValue: kind.rawValue), .auto)
      let set = HandSet(exercise: kind, reps: 12, at: 1000)
      XCTAssertEqual(HandSet(userInfo: set.userInfo), set)
      XCTAssertEqual(set.entry.exercise, kind)
    }
    XCTAssertEqual(ExerciseKind.analyzable.count, ExerciseKind.allCases.count - 2)
    // In Auto the count page reopens on the last typed exercise, count-only or not.
    let sitUps = HandSet(exercise: .sitUp, reps: 20, at: 2000)
    XCTAssertTrue(HandSet.start(mode: "auto", analyzed: nil, byHand: sitUps) == (.sitUp, 20))
  }

  /// #156, #157: a recorded set the camera got wrong (a pull-up set read as 0) becomes the lifter's own count,
  /// in place, and stops being a video.
  func testASetKeptByHandTakesTheLiftersCountAndDropsItsVideo() {
    let start = Date(timeIntervalSince1970: 5000)
    let recorded = RecentEntry(
      id: "330486D3", analyzedAt: start.addingTimeInterval(40), recordedAt: start, duration: 38, repCount: 0,
      bestScore: 71, source: .file(name: "clip.mov"), thumbnail: "thumb.jpg", exercise: .pullUp,
      originalName: "swing-recording.mov", originalBackup: "original.mov", analysisVersion: "2026-09-26.3",
      models: ["yolo26n-pose"], clipStartedAt: start)
    let kept = recorded.keptByHand(exercise: .pullUp, reps: 6)
    XCTAssertEqual(kept.id, recorded.id)
    XCTAssertEqual(kept.recordedAt, recorded.recordedAt)
    XCTAssertEqual(kept.analyzedAt, recorded.analyzedAt)
    XCTAssertEqual(kept.repCount, 6)
    XCTAssertEqual(kept.exercise, .pullUp)
    XCTAssertTrue(kept.isByHand)
    XCTAssertNil(kept.thumbnail)
    XCTAssertNil(kept.bestScore)
    XCTAssertNil(kept.originalBackup)
    XCTAssertNil(kept.analysisVersion)
    // The exercise can change too, and the count is clamped like the wrist's.
    XCTAssertEqual(recorded.keptByHand(exercise: .sitUp, reps: 0).exerciseKind, .sitUp)
    XCTAssertEqual(recorded.keptByHand(exercise: .sitUp, reps: 0).repCount, 1)
  }

  func testTheCountStopsAtOneAndTwoHundred() {
    XCTAssertEqual(HandSet.clamp(0), 1)
    XCTAssertEqual(HandSet.clamp(8), 8)
    XCTAssertEqual(HandSet.clamp(201), 200)
  }

  func testWithNoSetThePageOpensOnTenAndThePickersExercise() {
    XCTAssertTrue(HandSet.start(mode: "auto", analyzed: nil, byHand: nil) == (swing, 10))
    XCTAssertTrue(HandSet.start(mode: getUp.rawValue, analyzed: nil, byHand: nil) == (getUp, 10))
  }

  func testInAutoThePageOpensOnTheLastSet() {
    let analyzed = LastSet(reps: 3, exercise: getUp.definition.name, seconds: 90, at: 1000)
    XCTAssertTrue(HandSet.start(mode: "auto", analyzed: analyzed, byHand: nil) == (getUp, 3))
    // A fixed picker wins over the last set's exercise; the count is still the last set's.
    XCTAssertTrue(HandSet.start(mode: swing.rawValue, analyzed: analyzed, byHand: nil) == (swing, 3))
  }

  /// #183: the page reopens on the last set typed by hand, even after a filmed set of another exercise and
  /// whatever the picker says: typed sets are the ones between filmed ones.
  func testThePageReopensOnTheLastTypedSet() {
    let analyzed = LastSet(reps: 3, exercise: getUp.definition.name, seconds: 90, at: 1000)
    let earlier = HandSet(exercise: .pullUp, reps: 9, at: 900)
    XCTAssertTrue(HandSet.start(mode: "auto", analyzed: analyzed, byHand: earlier) == (.pullUp, 9))
    XCTAssertTrue(HandSet.start(mode: getUp.rawValue, analyzed: analyzed, byHand: earlier) == (.pullUp, 9))
  }

  func testAnAnalyzedCountOutsideTheRangeStartsClamped() {
    let big = LastSet(reps: 250, exercise: swing.definition.name, seconds: 600, at: 1000)
    let none = LastSet(reps: 0, exercise: swing.definition.name, seconds: 20, at: 1000)
    XCTAssertEqual(HandSet.start(mode: "auto", analyzed: big, byHand: nil).reps, 200)
    XCTAssertEqual(HandSet.start(mode: "auto", analyzed: none, byHand: nil).reps, 1)
  }

  func testTheSetCrossesAsUserInfo() throws {
    let set = HandSet(id: "abc", exercise: swing, reps: 8, at: 1234.5)
    XCTAssertEqual(HandSet(userInfo: set.userInfo), set)
    // The watch's log lines share the channel and are not sets.
    XCTAssertNil(HandSet(userInfo: ["watch_log": "command", "watch_t": 1.0]))
  }

  func testThePhonesEntryHasNoClipNoScoreAndIsNeverStale() {
    let entry = HandSet(id: "abc", exercise: swing, reps: 8, at: 5000).entry
    XCTAssertTrue(entry.isByHand)
    XCTAssertFalse(entry.isInPhotos)
    XCTAssertNil(entry.bestScore)
    XCTAssertNil(entry.thumbnail)
    XCTAssertEqual(entry.repCount, 8)
    XCTAssertEqual(entry.span, Date(timeIntervalSince1970: 5000)...Date(timeIntervalSince1970: 5000))
    XCTAssertFalse(entry.isStale(currentVersion: AnalysisVersion.current))
    XCTAssertFalse(entry.isStale(currentVersion: "some later analyzer"))
  }

  func testARepeatDeliveryIsOneSetAndTheIndexKeepsIt() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let recorded = RecentEntry(
      id: "rec", analyzedAt: Date(timeIntervalSince1970: 4000), recordedAt: nil, duration: 30, repCount: 10,
      bestScore: 80, source: .file(name: "clip.mov"), thumbnail: nil, exercise: swing, originalName: nil,
      analysisVersion: AnalysisVersion.current, models: ["yolo26n-pose"])
    var index = RecentsIndex(entries: [recorded])
    let set = HandSet(id: "abc", exercise: getUp, reps: 2, at: 5000)
    XCTAssertTrue(index.add(set))
    XCTAssertFalse(index.add(set))
    XCTAssertEqual(index.entries.map(\.id), ["abc", "rec"])
    try index.save(root: root)
    var loaded = RecentsIndex.load(root: root)
    XCTAssertEqual(loaded.entries.map(\.id), ["abc", "rec"])
    XCTAssertTrue(loaded.entries[0].isByHand)
    XCTAssertEqual(loaded.entries[0].exercise, getUp)
    // The launch backfill has no analysis.json to read for it and leaves it alone.
    XCTAssertFalse(loaded.backfill(root: root))
  }

  func testAnIndexFromBeforeTheWristStillDecodes() throws {
    let old = #"[{"id":"a","analyzedAt":0,"duration":30,"repCount":10,"bestScore":80,"source":{"file":{"name":"clip.mov"}}}]"#
    let entries = try JSONDecoder().decode([RecentEntry].self, from: Data(old.utf8))
    XCTAssertEqual(entries.map(\.id), ["a"])
    XCTAssertFalse(entries[0].isByHand)
  }

  func testRemovingItSaysThereIsNoVideo() {
    let prompt = SetDeletionPrompt(for: HandSet(exercise: swing, reps: 8, at: 5000).entry)
    XCTAssertFalse(prompt.isFinal)
    XCTAssertEqual(prompt.title, "Remove this set from Workouts?")
    XCTAssertEqual(prompt.confirm, "Remove")
  }

  func testTheWorkoutCountsItAndATapNearItOpensTheRecordedSet() {
    let workout = StoredWorkout(start: Date(timeIntervalSince1970: 1000), end: Date(timeIntervalSince1970: 2000))
    let recorded = RecentEntry(
      id: "rec", analyzedAt: Date(timeIntervalSince1970: 1130), recordedAt: nil, duration: 30, repCount: 10,
      bestScore: 80, source: .file(name: "clip.mov"), thumbnail: nil, exercise: swing, originalName: nil,
      clipStartedAt: Date(timeIntervalSince1970: 1100))
    let typed = HandSet(id: "hand", exercise: swing, reps: 8, at: 1140).entry
    let timeline = WorkoutTimeline(workout: workout, sets: [recorded, typed], heartRate: nil)
    XCTAssertEqual(timeline.rows.map(\.id), ["rec", "hand"])
    XCTAssertEqual(timeline.rows.map(\.byHand), [false, true])
    XCTAssertEqual(timeline.rows.reduce(0) { $0 + $1.reps }, 18)
    XCTAssertEqual(timeline.row(near: Date(timeIntervalSince1970: 1140), slop: 20)?.id, "rec")
    XCTAssertNil(timeline.row(near: Date(timeIntervalSince1970: 1200), slop: 20))
  }

  /// #178: a tap on the chart that hits no set adds one at that moment, starting from the set before it.
  func testATapOnEmptyChartDraftsASetAtThatMomentLikeTheOneBefore() {
    let workout = StoredWorkout(start: Date(timeIntervalSince1970: 1000), end: Date(timeIntervalSince1970: 2000))
    let recorded = RecentEntry(
      id: "rec", analyzedAt: Date(timeIntervalSince1970: 1130), recordedAt: nil, duration: 30, repCount: 12,
      bestScore: 80, source: .file(name: "clip.mov"), thumbnail: nil, exercise: getUp, originalName: nil,
      clipStartedAt: Date(timeIntervalSince1970: 1100))
    let typed = HandSet(id: "hand", exercise: .pullUp, reps: 5, at: 1500).entry
    let timeline = WorkoutTimeline(workout: workout, sets: [recorded, typed], heartRate: nil)
    let draft = timeline.handSet(at: Date(timeIntervalSince1970: 1300))
    XCTAssertEqual(draft.at, 1300)
    XCTAssertEqual(draft.exercise, getUp)
    XCTAssertEqual(draft.reps, 12)
    XCTAssertEqual(timeline.handSet(at: Date(timeIntervalSince1970: 1600)).exercise, .pullUp)
    // Before every set: the first set's; with no set: a swing set of 10.
    XCTAssertEqual(timeline.handSet(at: Date(timeIntervalSince1970: 1050)).exercise, getUp)
    let empty = WorkoutTimeline(workout: workout, sets: [], heartRate: nil).handSet(at: Date(timeIntervalSince1970: 1050))
    XCTAssertEqual(empty.exercise, swing)
    XCTAssertEqual(empty.reps, HandSet.defaultReps)
  }

  /// Story 066 (#102): the weight is set when the bell changes; later sets of the exercise in the workout show it as
  /// inherited, another exercise does not, the load counts reps × kg, and keeping a set by hand keeps its weight.
  func testTheBellsWeightCarriesForwardWithinAnExerciseAndCountsTheLoad() {
    let workout = StoredWorkout(start: Date(timeIntervalSince1970: 1000), end: Date(timeIntervalSince1970: 3000))
    func set(_ id: String, _ kind: ExerciseKind, reps: Int, at: Double, kg: Int? = nil) -> RecentEntry {
      var entry = RecentEntry(
        id: id, analyzedAt: Date(timeIntervalSince1970: at + 40), recordedAt: nil, duration: 30, repCount: reps,
        bestScore: 80, source: .file(name: "clip.mov"), thumbnail: nil, exercise: kind, originalName: nil,
        clipStartedAt: Date(timeIntervalSince1970: at))
      entry.bellKg = kg
      return entry
    }
    let timeline = WorkoutTimeline(
      workout: workout,
      sets: [
        set("s1", swing, reps: 10, at: 1100), set("s2", swing, reps: 10, at: 1200, kg: 24),
        set("s3", swing, reps: 12, at: 1300), set("g1", getUp, reps: 2, at: 1400),
        set("s4", swing, reps: 8, at: 1500, kg: 28), set("s5", swing, reps: 8, at: 1600),
      ],
      heartRate: nil)
    XCTAssertEqual(timeline.rows.map(\.kg), [nil, 24, 24, nil, 28, 28])
    XCTAssertEqual(timeline.rows.map(\.kgInherited), [false, false, true, false, false, true])
    XCTAssertEqual(timeline.loadKg, 10 * 24 + 12 * 24 + 8 * 28 + 8 * 28)
    XCTAssertNil(WorkoutTimeline(workout: workout, sets: [set("s1", swing, reps: 10, at: 1100)], heartRate: nil).loadKg)
    XCTAssertEqual(set("k", swing, reps: 10, at: 1100, kg: 16).keptByHand(exercise: swing, reps: 9).bellKg, 16)
    // An index from before 066 has no weight and still decodes.
    let old = #"[{"id":"a","analyzedAt":0,"duration":30,"repCount":10,"bestScore":80,"source":{"file":{"name":"clip.mov"}}}]"#
    XCTAssertNil(try JSONDecoder().decode([RecentEntry].self, from: Data(old.utf8))[0].bellKg)
  }

  /// #178 (Igor, 2026-09-30, on review): a tap on a typed set's mark opens that set, not a second add; a recorded
  /// set in reach still takes the tap first.
  func testATapNearATypedSetsMarkFindsThatSet() {
    let workout = StoredWorkout(start: Date(timeIntervalSince1970: 1000), end: Date(timeIntervalSince1970: 2000))
    let recorded = RecentEntry(
      id: "rec", analyzedAt: Date(timeIntervalSince1970: 1130), recordedAt: nil, duration: 30, repCount: 10,
      bestScore: 80, source: .file(name: "clip.mov"), thumbnail: nil, exercise: swing, originalName: nil,
      clipStartedAt: Date(timeIntervalSince1970: 1100))
    let typed = HandSet(id: "hand", exercise: .pullUp, reps: 5, at: 1500).entry
    let timeline = WorkoutTimeline(workout: workout, sets: [recorded, typed], heartRate: nil)
    XCTAssertEqual(timeline.typedRow(near: Date(timeIntervalSince1970: 1510), slop: 20)?.id, "hand")
    XCTAssertNil(timeline.row(near: Date(timeIntervalSince1970: 1510), slop: 20))
    XCTAssertNil(timeline.typedRow(near: Date(timeIntervalSince1970: 1600), slop: 20))
    XCTAssertNil(timeline.typedRow(near: Date(timeIntervalSince1970: 1120), slop: 20))
  }
}
