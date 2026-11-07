import Foundation

#if canImport(os)
  import os
#endif

/// The one owner of the models (#147): the pose model and the detectors are shared, mutable instances, safe on one
/// job at a time. An offline pass holds the lease for its whole run and a new pass waits for it (FIFO), so a
/// cancelled worker still inside its last frame finishes that frame before the next pass touches the models. The
/// live camera path never waits: it takes the lease per frame with `tryAcquire` and skips the frame when a pass
/// holds it. Within one holder the models may still run side by side (pose and bell on two threads, 3ba7902).
public final class ModelLease: Sendable {
  private struct State: Sendable {
    var held = false
    var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  public init() {}

  /// Whether some job holds the lease now (for tests and logs; stale as soon as it returns).
  public var isHeld: Bool { state.withLock { $0.held } }

  /// Takes the lease now if it is free and nobody is queued; never waits.
  public func tryAcquire() -> Bool {
    state.withLock { state in
      guard !state.held else { return false }
      state.held = true
      return true
    }
  }

  /// Waits in line for the lease. Throws `CancellationError` if the task is cancelled before or while waiting,
  /// and the lease is then not held by the caller, with one exception: a cancel that lands in the same instant
  /// `release()` hands the lease over returns normally with the lease held, so callers `defer { release() }`.
  public func acquire() async throws {
    try Task.checkCancellation()
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        let granted: Bool? = state.withLock { state in
          // The cancellation flag is set before the handler runs, so a cancel that lands before this append is
          // seen here and one that lands after finds the waiter below.
          if Task.isCancelled { return nil }
          guard state.held else {
            state.held = true
            return true
          }
          state.waiters.append((id, continuation))
          return false
        }
        switch granted {
        case .some(true): continuation.resume()
        case .none: continuation.resume(throwing: CancellationError())
        case .some(false): break
        }
      }
    } onCancel: {
      let waiter = state.withLock { state -> CheckedContinuation<Void, Error>? in
        guard let index = state.waiters.firstIndex(where: { $0.id == id }) else { return nil }
        return state.waiters.remove(at: index).continuation
      }
      waiter?.resume(throwing: CancellationError())
    }
  }

  /// Hands the lease to the longest waiter, or frees it. Call exactly once per successful acquire.
  public func release() {
    let next = state.withLock { state -> CheckedContinuation<Void, Error>? in
      guard !state.waiters.isEmpty else {
        state.held = false
        return nil
      }
      return state.waiters.removeFirst().continuation  // stays held: ownership passes straight to the waiter
    }
    next?.resume()
  }
}
