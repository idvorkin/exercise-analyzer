//  Linux only (just test-linux): the two Apple types ExerciseCore names that Linux lacks. Foundation there has
//  CGFloat, CGPoint, CGSize and CGRect; on Apple platforms CoreGraphics and os have these, so nothing here is built.

import Foundation

#if !canImport(CoreGraphics)
  /// A rep's still. The analyzers only carry one along; the host tests pass none, and Linux has no images.
  public final class CGImage: Sendable {}
#endif

#if !canImport(os)
  /// ModelLease's lock, over NSLock: the same `withLock` the os one offers.
  final class OSAllocatedUnfairLock<State>: @unchecked Sendable {
    private var state: State
    private let lock = NSLock()

    init(initialState: State) { state = initialState }

    func withLock<R>(_ body: (inout State) throws -> R) rethrows -> R {
      lock.lock()
      defer { lock.unlock() }
      return try body(&state)
    }
  }
#endif
