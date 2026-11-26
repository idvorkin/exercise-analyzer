// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Live heart rate started and ended from another app (story 092, context-grabber-at59; Larry, 2026-11-26:
//  Grabber starts it as a call starts and ends it as the call ends). Health opens a watch app only for its own
//  phone app, so the door is Exercise Analyzer's: a link (`exerciseanalyzer://live-heart-rate/start?kind=call`,
//  `…/end`) and two Shortcuts actions. The phone opens the watch app with a workout configuration that says which
//  light session (090) to start; the watch builds its own session from that. The end goes to the watch as a
//  message of its own through the running session, naming the session by its start.

import Foundation

public enum LiveLaunch {
  public static let scheme = "exerciseanalyzer"
  public static let host = "live-heart-rate"

  public enum Action: Equatable, Sendable {
    /// Start a light session: a call or a walk, or nil for the watch's own choice (Motion, as a tap on Live).
    case start(WorkoutKind?)
    case end
  }

  /// A light session's kind as asked for, or nil for any other word.
  public static func kind(_ word: String?) -> WorkoutKind? {
    guard let word, let kind = WorkoutKind(rawValue: word.lowercased()), kind == .call || kind == .walk else {
      return nil
    }
    return kind
  }

  /// The link another app opens, with the caller's way back (x-callback-url's `x-success` and `x-error`).
  public struct Request: Equatable, Sendable {
    public var action: Action
    public var success: URL?
    public var error: URL?

    public init(action: Action, success: URL? = nil, error: URL? = nil) {
      self.action = action
      self.success = success
      self.error = error
    }

    /// Nil for any link that is not Live heart rate's.
    public init?(url: URL) {
      guard url.scheme?.lowercased() == LiveLaunch.scheme, url.host?.lowercased() == LiveLaunch.host,
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
      else { return nil }
      let items = parts.queryItems ?? []
      let value = { (name: String) in items.first { $0.name == name }?.value }
      switch url.path.lowercased() {
      case "/start": action = .start(LiveLaunch.kind(value("kind")))
      case "/end": action = .end
      default: return nil
      }
      success = value("x-success").flatMap(URL.init(string:))
      error = value("x-error").flatMap(URL.init(string:))
    }

    /// Where to send the caller once the watch has been asked: `x-success`, or `x-error` with `errorMessage`
    /// (falling back to `x-success` when no `x-error` was given); nil when the caller asked for no way back.
    public func back(error message: String?) -> URL? {
      guard let message else { return success }
      guard let target = error ?? success,
        var parts = URLComponents(url: target, resolvingAgainstBaseURL: false)
      else { return nil }
      parts.queryItems = (parts.queryItems ?? []) + [URLQueryItem(name: "errorMessage", value: message)]
      return parts.url
    }
  }

  /// What the watch starts on a launch from the phone.
  public enum Choice: Equatable, Sendable {
    case kind(WorkoutKind)
    /// Motion decides, as a tap on Live does.
    case motion
  }

  // Health's raw values: HKWorkoutSessionLocationType unknown 1, indoor 2, outdoor 3.
  static let unknownLocation = 1
  static let indoorLocation = 2
  static let outdoorLocation = 3

  /// The workout configuration the phone opens the watch app with: Health's activity type and location type
  /// raw values. A call is "other" at an unknown place, a walk is walking outdoors (as their sessions are, 090),
  /// and the watch's own choice is "other" indoors.
  public static func configuration(kind: WorkoutKind?) -> (activity: UInt, location: Int) {
    switch kind {
    case .call: (WorkoutKind.call.healthActivity, unknownLocation)
    case .walk: (WorkoutKind.walk.healthActivity, outdoorLocation)
    default: (WorkoutKind.call.healthActivity, indoorLocation)
    }
  }

  /// What a launch's configuration asks for; anything this build does not know is the watch's own choice.
  public static func choice(activity: UInt, location: Int) -> Choice {
    switch (WorkoutKind(healthActivity: activity), location) {
    case (.call, unknownLocation): .kind(.call)
    case (.walk, outdoorLocation): .kind(.walk)
    default: .motion
    }
  }

  /// The end of a light session, sent once through the running session's own channel (never in the status the
  /// phone keeps resending, so an old copy cannot end a later session). It names the session by its start; a
  /// watch build before 092 cannot read it as a status and drops it.
  public struct End: Codable, Equatable, Sendable {
    public var endLiveStartedAt: Double

    public init(startedAt: Double) { endLiveStartedAt = startedAt }

    public init?(data: Data) {
      guard let end = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
      self = end
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }

    /// How far the phone's copy of the start may sit from the wrist's.
    public static let startTolerance: TimeInterval = 2

    /// Only a light session (090) ends from outside, and only the one this names: a gym hour or any other
    /// workout never does.
    public func ends(light: Bool, startedAt: Date?) -> Bool {
      guard light, let startedAt else { return false }
      return abs(startedAt.timeIntervalSince1970 - endLiveStartedAt) < Self.startTolerance
    }
  }
}
