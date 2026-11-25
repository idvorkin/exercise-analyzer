// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  A barbell set's weight (story 083, #377; Igor, 2026-11-24: "That can be my barbell weight input"): the bar and
//  the plates on one side, in pounds, as the gym's plates are; the app adds it up. A set's weight is a bell or a
//  barbell, never both (`SetWeight`); the load and the progression count a barbell at its weight in kg.

import Foundation

/// The bar under the plates: Igor's three.
public enum BarKind: String, Codable, CaseIterable, Sendable {
  case regular
  case safetySquat = "safety-squat"
  /// #375: "show full weight x2 + 65", the reverse lunges' bar.
  case sixtyFive = "65-lb"

  /// The bar's own weight: a standard 45 lb bar, Igor's safety squat bar at 58 lb, and the 65 lb bar.
  public var lb: Int {
    switch self {
    case .regular: 45
    case .safetySquat: 58
    case .sixtyFive: 65
    }
  }

  public var name: String {
    switch self {
    case .regular: "Barbell"
    case .safetySquat: "Safety squat bar"
    case .sixtyFive: "65 lb bar"
    }
  }

  /// What a tile or a segment has room for: "Barbell 45", "SSB 58", "Bar 65".
  public var short: String {
    switch self {
    case .regular: "Barbell 45"
    case .safetySquat: "SSB 58"
    case .sixtyFive: "Bar 65"
    }
  }
}

public struct BarbellLoad: Codable, Hashable, Sendable {
  /// The gym's plates, heaviest first: the plate buttons, and the only plates a load holds.
  public static let plateSizes = [45, 35, 25, 10]
  /// What the sheet opens on with no barbell weight before it: a 45 a side on the regular bar.
  public static let start = BarbellLoad(bar: .regular, plates: [45])
  public static let lbPerKg = 2.20462262

  public var bar: BarKind
  /// The plates on one side in lb, heaviest first; the other side is the same.
  public private(set) var plates: [Int]

  public init(bar: BarKind, plates: [Int] = []) {
    self.bar = bar
    self.plates = Self.normalized(plates)
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(bar: try c.decode(BarKind.self, forKey: .bar), plates: try c.decode([Int].self, forKey: .plates))
  }

  private static func normalized(_ plates: [Int]) -> [Int] {
    plates.filter { plateSizes.contains($0) }.sorted(by: >)
  }

  public func count(of plate: Int) -> Int { plates.filter { $0 == plate }.count }

  /// The most plates a side takes from a tap (#387; Igor tapped his way to 45 ×15, 1,448 lb: "Obvious can't go up
  /// this high"): 8 a side, 765 lb on the barbell in 45s. Only `add` holds to it: a load stored or synced with
  /// more is kept as it is.
  public static let maxPlatesPerSide = 8

  /// The side has as many plates as a tap may put on it.
  public var isFull: Bool { plates.count >= Self.maxPlatesPerSide }

  /// One more of `plate` on each side; a plate the gym doesn't have, or a full side, is ignored.
  public mutating func add(_ plate: Int) {
    guard !isFull else { return }
    plates = Self.normalized(plates + [plate])
  }

  /// One `plate` off each side; none left is none.
  public mutating func remove(_ plate: Int) {
    guard let at = plates.firstIndex(of: plate) else { return }
    plates.remove(at: at)
  }

  /// Every plate off: the bar alone ("Empty bar", #387).
  public mutating func empty() { plates = [] }

  public var perSideLb: Int { plates.reduce(0, +) }
  public var totalLb: Int { bar.lb + 2 * perSideLb }
  /// The total in whole kg, for the load and the progression.
  public var kg: Int { Int((Double(totalLb) / Self.lbPerKg).rounded()) }

  /// "45/side", "45+10/side", or "empty bar".
  public var sideLabel: String {
    plates.isEmpty ? "empty bar" : plates.map(String.init).joined(separator: "+") + "/side"
  }
}

/// A set's weight: the bell's in kg (066) or a barbell's plates (083).
public enum SetWeight: Hashable, Sendable {
  case bell(Int)
  case barbell(BarbellLoad)

  /// What it counts for in kg: the bell, or the barbell's total converted.
  public var kg: Int {
    switch self {
    case .bell(let kg): kg
    case .barbell(let load): load.kg
    }
  }

  /// "24 kg", "148 lb".
  public var label: String {
    switch self {
    case .bell(let kg): "\(kg) kg"
    case .barbell(let load): "\(load.totalLb) lb"
    }
  }

  /// What VoiceOver says: "24 kilograms", "148 pounds, safety squat bar, 45 per side".
  public var spoken: String {
    switch self {
    case .bell(let kg): return "\(kg) kilograms"
    case .barbell(let load):
      let side = load.plates.isEmpty ? "empty" : load.plates.map(String.init).joined(separator: " and ") + " per side"
      return "\(load.totalLb) pounds, \(load.bar.name.lowercased()), \(side)"
    }
  }

  public var bellKg: Int? {
    if case .bell(let kg) = self { return kg }
    return nil
  }

  public var barbell: BarbellLoad? {
    if case .barbell(let load) = self { return load }
    return nil
  }
}

extension RecentEntry {
  /// The set's own weight, a bell's or a barbell's; nil when never set.
  public var weight: SetWeight? { barbell.map(SetWeight.barbell) ?? bellKg.map(SetWeight.bell) }

  /// The lifter set the set's weight on `device` (066, 083); nil clears it. A bell's replaces any plates and
  /// plates replace any bell: one weight per set, with one edit time.
  public mutating func setWeight(_ weight: SetWeight?, by device: String, at time: Date = Date()) {
    bellKg = weight?.bellKg
    barbell = weight?.barbell
    bellKgEditedAt = time
    edited(by: device, at: time)
  }

  /// Each exercise's last weight, bell or barbell, the newest set's own of it in any workout: what the phone's
  /// by-hand sheet opens on (#271, 083). The wrist's bells stay `lastBellKg`.
  public static func lastWeight(_ entries: [RecentEntry]) -> [ExerciseKind: SetWeight] {
    var newest: [ExerciseKind: (at: Date, weight: SetWeight)] = [:]
    for entry in entries {
      guard let weight = entry.weight else { continue }
      let at = entry.span.lowerBound
      if let seen = newest[entry.exerciseKind], seen.at >= at { continue }
      newest[entry.exerciseKind] = (at, weight)
    }
    return newest.mapValues(\.weight)
  }

  /// Each exercise's last plates, where they are its newest weight: what the phone tells the wrist beside
  /// `lastBellKg` (`WatchStatus.barbell`, story 086).
  public static func lastPlates(_ entries: [RecentEntry]) -> [ExerciseKind: BarbellLoad] {
    lastWeight(entries).compactMapValues(\.barbell)
  }
}
