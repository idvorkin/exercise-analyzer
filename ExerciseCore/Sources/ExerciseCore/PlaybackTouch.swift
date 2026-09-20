import Foundation

/// One touch owner for the whole playback picture. The app supplies the 0.3 s hold timer and
/// executes these actions; the policy is replayable on the host without a screen or a run loop.
public struct PlaybackTouch {
  public enum Side: Equatable { case previous, next }
  public enum Key: Int, CaseIterable { case rep, frame, position }
  public struct Target: Equatable {
    public let side: Side
    public let key: Key
    public init(side: Side, key: Key) { self.side = side; self.key = key }
  }
  public enum Action: Equatable {
    case showStacks, dismiss, tap(Side?), activate(Target?), end
  }

  public static let holdSeconds = 0.3
  public static let edgeFraction = 0.24
  public static let margin = 12.0
  private var start: CGPoint?
  private var location = CGPoint.zero
  private var size = CGSize.zero
  private var stacksWereUp = false
  private var held = false
  private var moved = false
  private var usedKey = false
  private var active: Target?

  public init() {}

  public mutating func begin(at point: CGPoint, size: CGSize, stacksUp: Bool) -> [Action] {
    self = Self()
    start = point
    location = point
    self.size = size
    stacksWereUp = stacksUp
    return stacksUp ? track() : []
  }

  public mutating func move(to point: CGPoint) -> [Action] {
    guard let start else { return [] }
    location = point
    if abs(point.x - start.x) >= 20 || abs(point.y - start.y) >= 20 { moved = true }
    return held || stacksWereUp ? track() : []
  }

  public mutating func hold() -> [Action] {
    guard start != nil, !held, stacksWereUp || !moved else { return [] }
    held = true
    return (stacksWereUp ? [] : [.showStacks]) + track()
  }

  public mutating func end() -> [Action] {
    guard let start else { return [] }
    var actions: [Action] = []
    if !held, !moved, !usedKey {
      actions.append(stacksWereUp ? .dismiss : .tap(Self.target(at: start, in: size)?.side))
    }
    self = Self()
    return actions + [.end]
  }

  public mutating func cancel() -> [Action] {
    self = Self()
    return [.end]
  }

  private mutating func track() -> [Action] {
    let next = Self.target(at: location, in: size, keeping: active)
    guard next != active else { return [] }
    active = next
    if next != nil { usedKey = true }
    return [.activate(next)]
  }

  /// The same 24% edge zones and thirds as the drawn stacks. A small re-entry margin keeps a
  /// jittery thumb on its current key; crossing the picture always reaches the opposite stack.
  public static func target(at p: CGPoint, in size: CGSize, keeping active: Target? = nil) -> Target? {
    guard size.width > 0, size.height > 0,
      p.x >= -margin, p.x <= size.width + margin,
      p.y >= -margin, p.y <= size.height + margin else { return nil }
    let edge = size.width * edgeFraction
    let side: Side
    if p.x < edge { side = .previous }
    else if p.x > size.width - edge { side = .next }
    else if active?.side == .previous, p.x < edge + margin { side = .previous }
    else if active?.side == .next, p.x > size.width - edge - margin { side = .next }
    else { return nil }
    let height = size.height / 3
    var row = min(2, max(0, Int(floor(p.y / height))))
    if let active, active.side == side,
      p.y >= Double(active.key.rawValue) * height - margin,
      p.y < Double(active.key.rawValue + 1) * height + margin {
      row = active.key.rawValue
    }
    return Target(side: side, key: Key(rawValue: row)!)
  }
}
