import Foundation

/// The camera's frames waiting for the main thread (#94). The capture queue offers every frame and the main actor
/// drains them; at most `capacity` wait, so a main-thread hang holds that many of the camera's buffers and no more,
/// and the pool the recorder also draws from never runs dry. The newest frames win (the live count wants the
/// present, not the backlog), and one drain is scheduled per batch, not one task per frame. Skipped frames are the
/// live analysis's only: the recorder takes every frame on the capture queue before it is offered here.
/// Skips roll up per whole second of camera time, so the log says how much a stall cost without a line per frame.
public final class FrameBacklog<Frame>: @unchecked Sendable {
  /// Frames skipped in one second of camera time (`second` is the floor of the frames' timestamps).
  public struct SkipReport: Equatable, Sendable {
    public let second: Int
    public let skipped: Int

    public init(second: Int, skipped: Int) {
      self.second = second
      self.skipped = skipped
    }
  }

  /// What the capture queue does after an offer: schedule a drain on the main actor, and log a closed second.
  public struct Offer {
    public let needsDrain: Bool
    public let report: SkipReport?
  }

  private struct State {
    var frames: [Frame] = []
    var drainScheduled = false
    var openSecond: Int?
    var openSkipped = 0
    var skippedTotal = 0
  }

  public let capacity: Int
  // Frames are pixel buffers, which are not Sendable; they only move between the capture queue and the main actor
  // under this lock.
  private let lock = NSLock()
  private var current = State()

  public init(capacity: Int = 2) {
    precondition(capacity > 0)
    self.capacity = capacity
  }

  /// Frames skipped since the last reset.
  public var skippedTotal: Int { withState { $0.skippedTotal } }

  /// Adds a frame taken at `time` (seconds). Over capacity the oldest waiting frame is skipped.
  public func offer(_ frame: Frame, at time: Double) -> Offer {
    let capacity = capacity
    return withState { state in
      let second = Int(time.rounded(.down))
      var report: SkipReport?
      if let open = state.openSecond, second != open, state.openSkipped > 0 {
        report = SkipReport(second: open, skipped: state.openSkipped)
        state.openSkipped = 0
        state.openSecond = nil
      }
      state.frames.append(frame)
      if state.frames.count > capacity {
        state.frames.removeFirst(state.frames.count - capacity)
        state.skippedTotal += 1
        state.openSecond = second
        state.openSkipped += 1
      }
      let needsDrain = !state.drainScheduled
      state.drainScheduled = true
      return Offer(needsDrain: needsDrain, report: report)
    }
  }

  /// Takes every waiting frame, oldest first; the next offer schedules a new drain.
  public func drain() -> [Frame] {
    withState { state in
      let frames = state.frames
      state.frames = []
      state.drainScheduled = false
      return frames
    }
  }

  /// The second still open with skips in it, reported once (at the end of a set).
  public func flush() -> SkipReport? {
    withState { state in
      guard let open = state.openSecond, state.openSkipped > 0 else { return nil }
      let report = SkipReport(second: open, skipped: state.openSkipped)
      state.openSecond = nil
      state.openSkipped = 0
      return report
    }
  }

  /// A new set: no frames waiting, nothing skipped.
  public func reset() {
    withState { $0 = State() }
  }

  private func withState<R>(_ body: (inout State) -> R) -> R {
    lock.lock()
    defer { lock.unlock() }
    return body(&current)
  }
}
