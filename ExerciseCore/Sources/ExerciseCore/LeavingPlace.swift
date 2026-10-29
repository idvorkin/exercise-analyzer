// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  End when I leave (story 079, #332; Igor: "Gym can be where we start the workout"): the first good fix after
//  Start is the gym; two good fixes in a row well beyond it are leaving, ended at the last fix still inside.

import Foundation

public struct LeavingPlace: Equatable, Sendable {
  /// How far from the start counts as gone: a gym and its car park fit inside.
  public static let radius: Double = 300
  /// Fixes vaguer than this say nothing, either way.
  public static let goodAccuracy: Double = 100
  /// Good fixes in a row beyond the radius before it ends: one stray fix does not.
  public static let fixesAway = 2

  public struct Fix: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var accuracy: Double
    public var at: Date
    public init(latitude: Double, longitude: Double, accuracy: Double, at: Date) {
      self.latitude = latitude
      self.longitude = longitude
      self.accuracy = accuracy
      self.at = at
    }
  }

  /// Where the workout started: the first good fix.
  public private(set) var place: Fix?
  /// The last good fix inside the radius.
  public private(set) var lastInside: Date?
  public private(set) var left = false
  private var away = 0

  public init() {}

  /// A fix from the watch; the time it left, the last fix still inside, once, when this one decides it.
  public mutating func fix(_ fix: Fix) -> Date? {
    guard !left, fix.accuracy >= 0, fix.accuracy <= Self.goodAccuracy else { return nil }
    guard let place else {
      place = fix
      lastInside = fix.at
      return nil
    }
    // Beyond the radius by more than this fix's own doubt.
    if Self.meters(from: place, to: fix) > Self.radius + fix.accuracy {
      away += 1
    } else {
      away = 0
      lastInside = fix.at
    }
    guard away >= Self.fixesAway else { return nil }
    left = true
    return lastInside ?? place.at
  }

  /// Great-circle distance in meters (haversine).
  public static func meters(from a: Fix, to b: Fix) -> Double {
    let radians = Double.pi / 180
    let dLat = (b.latitude - a.latitude) * radians
    let dLon = (b.longitude - a.longitude) * radians
    let h =
      sin(dLat / 2) * sin(dLat / 2) + cos(a.latitude * radians) * cos(b.latitude * radians) * sin(dLon / 2)
      * sin(dLon / 2)
    return 2 * 6_371_000 * asin(min(1, sqrt(h)))
  }
}
