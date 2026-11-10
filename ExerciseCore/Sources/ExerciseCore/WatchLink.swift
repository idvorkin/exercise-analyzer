// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The watch's link to the phone as one value (the 2026-11-07 state-machine audit, finding 5): what the wrist makes
//  of reachability, the age of the last status and the age of the raise. The watch app's `PhoneLink` used to work
//  it out in three computed Bools (`isLive`, `showsAsLive`, `answersLost`) that nine places read in different mixes,
//  and only the screenshot rung could show which page the rules picked. Here the host tests the 8 s stale limit,
//  the 2 s wake grace and "not answering" row by row (`WatchLinkTests`).

import Foundation

public enum WatchLink: Equatable, Sendable {
  /// Reachable, and a status came within `maxStatusAge`: its status and the recording controls are trusted.
  case live
  /// Not live yet, but the wrist came up less than `wakeGrace` ago and has heard from the phone before: the screen
  /// keeps what it last knew rather than flash "Not connected" while the link comes back.
  case waking
  /// The phone reads reachable but has stopped answering, mid-set (#137): the link can die one way, the phone's
  /// sends failing while every tap from here still arrives, so the recording controls stay.
  case notAnswering
  /// Reachable, not answering, not recording: "Waiting for the phone…".
  case waiting
  /// Not reachable: "Not connected to the phone".
  case disconnected

  /// A status older than this is stale: the phone app may be gone without having sent an idle status.
  public static let maxStatusAge: TimeInterval = 8
  /// How long a raised wrist shows what it last knew before it says "not connected": the link comes back ~0.5 s
  /// after the raise (≤ 1.1 s over 32 raises at the gym, 2026-09-22), fresh status one round trip later.
  public static let wakeGrace: TimeInterval = 2

  /// - Parameters:
  ///   - statusAge: seconds since the last status from the phone; nil when none was heard since launch.
  ///   - wakeAge: seconds since the watch app last came to the front.
  ///   - recording: the last status heard says the camera is up.
  public static func of(reachable: Bool, statusAge: TimeInterval?, wakeAge: TimeInterval, recording: Bool) -> Self {
    if reachable, let statusAge, statusAge < maxStatusAge { return .live }
    if statusAge != nil, wakeAge < wakeGrace { return .waking }
    guard reachable else { return .disconnected }
    return recording ? .notAnswering : .waiting
  }

  /// The phone's status and the recording controls are trustworthy (a stored application context can say
  /// "recording" long after the fact).
  public var isLive: Bool { self == .live }
  /// What the screen trusts: a live phone, or the last status for the first seconds after a raise.
  public var showsAsLive: Bool { self == .live || self == .waking }
  /// The recording pages stay up, with the "PHONE NOT ANSWERING" hint, so Done and Cancel still reach the phone.
  public var answersLost: Bool { self == .notAnswering }
}
