// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  What the Settings sheet says under "Send workouts to Larry" (story 088, #392; Igor: "that sync switch is hidden
//  and doesn't work at all"): when Larry's Cockpit last took something, live event (084) or whole workout (087),
//  how many events wait, and what the Cockpit answered when it took nothing. Fed the sender's own log lines.

import Foundation

public struct LarrySendStatus: Codable, Equatable, Sendable {
  /// The last time the Cockpit took an event or a whole workout; kept across launches.
  public private(set) var lastSentAt: Date?
  /// What the Cockpit answered the last time it took nothing, until the next send; nil when all is well.
  public private(set) var problem: String?

  public init() {}

  /// One of the sender's answers, by its log line's `action` (`workout_event`, `workout_sync`): a send, a miss, a
  /// refusal, or the switch going off. Every other line (queued, planned, dropped) changes nothing.
  public mutating func record(action: String, reason: String?, at time: Date) {
    let why = reason.map { ": \($0)" } ?? ""
    switch action {
    case "sent":
      lastSentAt = time
      problem = nil
    case "waiting":
      problem = "No answer from Larry's Cockpit, trying again\(why)"
    case "not_yet":
      problem = "No answer from Larry's Cockpit"
    case "refused":
      problem = "Larry's Cockpit refused one\(why)"
    case "off":
      problem = nil
    default:
      break
    }
  }

  /// "On · last sent 4 min ago · 2 waiting", "On · nothing sent yet", "Off · nothing goes to Larry".
  public func line(enabled: Bool, waiting: Int, now: Date) -> String {
    guard enabled else { return "Off · nothing goes to Larry" }
    var parts = ["On", lastSentAt.map { "last sent \(Self.ago($0, now: now))" } ?? "nothing sent yet"]
    if waiting > 0 { parts.append("\(waiting) waiting") }
    return parts.joined(separator: " · ")
  }

  private static func ago(_ time: Date, now: Date) -> String {
    let seconds = max(0, now.timeIntervalSince(time))
    switch seconds {
    case ..<60: return "just now"
    case ..<3600: return "\(Int(seconds / 60)) min ago"
    case ..<86400: return "\(Int(seconds / 3600)) h ago"
    default:
      let days = Int(seconds / 86400)
      return days == 1 ? "1 day ago" : "\(days) days ago"
    }
  }
}
