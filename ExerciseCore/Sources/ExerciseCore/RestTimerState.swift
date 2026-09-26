import Foundation

/// The rest count and the identity a delayed permission reply must still own.
public struct RestTimerState: Sendable {
  public private(set) var id: UUID?
  public private(set) var endedAt: Date?
  public private(set) var deadline: Date?

  public init() {}

  @discardableResult
  public mutating func start(at date: Date, length: TimeInterval) -> UUID {
    let id = UUID()
    self.id = id
    endedAt = date
    deadline = date.addingTimeInterval(length)
    return id
  }

  public mutating func clear() {
    id = nil
    endedAt = nil
    deadline = nil
  }

  /// Nil means this reply is stale or missed its deadline: never tap late for a permission reply.
  public func remaining(for id: UUID, at now: Date) -> TimeInterval? {
    guard self.id == id, let deadline else { return nil }
    let remaining = deadline.timeIntervalSince(now)
    return remaining > 0 ? remaining : nil
  }
}
