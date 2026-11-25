// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Story 086 (#375): the wrist's Set by hand takes plates on a bar as the phone's does (083), and the 65 lb bar
//  joins the bars. The plates ride the typed set to the phone, by every road it takes, and the wrist opens on the
//  exercise's last weight, bell or plates.

import XCTest

@testable import ExerciseCore

final class WatchBarbellTests: XCTestCase {
  private let lunge = ExerciseKind.splitSquat
  private let swing = ExerciseKind.kettlebellSwing
  private var bar65: BarbellLoad { BarbellLoad(bar: .sixtyFive, plates: [45]) }

  func testTheSixtyFivePoundBarWithFortyFiveASideIs155() {
    XCTAssertEqual(BarKind.allCases, [.regular, .safetySquat, .sixtyFive])
    XCTAssertEqual(BarKind.sixtyFive.lb, 65)
    XCTAssertEqual(BarKind.sixtyFive.name, "65 lb bar")
    XCTAssertEqual(bar65.totalLb, 155, "#375: 2 × 45 + 65")
    XCTAssertEqual(SetWeight.barbell(bar65).spoken, "155 pounds, 65 lb bar, 45 per side")
    let back = try? JSONDecoder().decode(BarbellLoad.self, from: JSONEncoder().encode(bar65))
    XCTAssertEqual(back, bar65)
  }

  func testAWristTypedBarbellSetCrossesWithItsPlates() {
    let set = HandSet(exercise: lunge, reps: 8, at: 1000, weight: .barbell(bar65))
    let landed = HandSet(userInfo: set.userInfo)
    XCTAssertEqual(landed?.barbell, bar65)
    XCTAssertNil(landed?.kg)
    XCTAssertEqual(landed?.entry.weight, .barbell(bar65))
  }

  /// #197's net under the queued transfer: the set's JSON is found in a stuck transfer even with the plates'
  /// object nested inside it.
  func testABarbellSetIsReadOutOfAStuckTransfer() throws {
    let set = HandSet(id: "B1", exercise: lunge, reps: 8, at: 1000, weight: .barbell(bar65))
    let json = try XCTUnwrap(String(bytes: try JSONEncoder().encode(set), encoding: .utf8))
    let transfer = Data(("bplist00\u{1}set_by_hand\u{2}O\u{11}" + json + "\u{0}\u{8}trailer}").utf8)
    let sets = HandSet.typedSets(inStuckTransfer: transfer)
    XCTAssertEqual(sets.map(\.id), ["B1"])
    XCTAssertEqual(sets.first?.barbell, bar65)
  }

  func testTheWristOpensOnTheExercisesLastWeightPlatesIncluded() {
    let analyzed = LastSet(reps: 10, exercise: lunge.definition.name, seconds: 30, at: 1000)
    let bells = [swing.rawValue: 24]
    let plates = [lunge.rawValue: bar65]
    XCTAssertEqual(
      HandSet.startWeight(for: lunge, bells: bells, plates: plates, typed: nil, analyzed: analyzed), .barbell(bar65))
    XCTAssertEqual(
      HandSet.startWeight(for: swing, bells: bells, plates: plates, typed: nil, analyzed: analyzed), .bell(24))
    let typedLater = HandSet(exercise: lunge, reps: 8, at: 1100, weight: .bell(20))
    XCTAssertEqual(
      HandSet.startWeight(for: lunge, bells: bells, plates: plates, typed: typedLater, analyzed: analyzed), .bell(20))
    let typedEarlier = HandSet(exercise: lunge, reps: 8, at: 900, weight: .barbell(BarbellLoad(bar: .regular)))
    XCTAssertEqual(
      HandSet.startWeight(for: lunge, bells: bells, plates: plates, typed: typedEarlier, analyzed: analyzed),
      .barbell(bar65), "the phone's newer weight wins")
    XCTAssertEqual(
      HandSet.startWeight(for: lunge, bells: [:], plates: [:], typed: typedEarlier, analyzed: analyzed),
      .barbell(BarbellLoad(bar: .regular)))
    XCTAssertNil(HandSet.startWeight(for: .pullUp, bells: bells, plates: plates, typed: nil, analyzed: analyzed))
  }

  /// The phone tells the wrist each exercise's last plates beside its last bells, only where the plates are the
  /// newer weight; an older phone's status has none.
  func testThePhoneTellsTheWristTheLastPlates() throws {
    func set(_ kind: ExerciseKind, at: Double, weight: SetWeight) -> RecentEntry {
      var entry = HandSet(exercise: kind, reps: 10, at: at).entry
      entry.setWeight(weight, by: "phone", at: Date(timeIntervalSince1970: at))
      return entry
    }
    let entries = [
      set(lunge, at: 300, weight: .barbell(bar65)), set(lunge, at: 200, weight: .bell(24)),
      set(swing, at: 300, weight: .bell(24)), set(swing, at: 100, weight: .barbell(bar65)),
    ]
    XCTAssertEqual(RecentEntry.lastPlates(entries), [lunge: bar65])
    var status = WatchStatus.idle
    status.barbell = [lunge.rawValue: bar65]
    let decoded = try JSONDecoder().decode(WatchStatus.self, from: JSONEncoder().encode(status))
    XCTAssertEqual(decoded.barbell, [lunge.rawValue: bar65])
    let old = try JSONEncoder().encode(WatchStatus.idle)
    var dict = try XCTUnwrap(JSONSerialization.jsonObject(with: old) as? [String: Any])
    dict["barbell"] = nil
    let fromOld = try JSONDecoder().decode(WatchStatus.self, from: JSONSerialization.data(withJSONObject: dict))
    XCTAssertEqual(fromOld.barbell, [:])
  }
}
