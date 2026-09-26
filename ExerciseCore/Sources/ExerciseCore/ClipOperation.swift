import Foundation

/// Main-actor owners carry this immutable target across suspension points. Starting another operation,
/// even on the same entry, invalidates every publication from the previous one.
public struct ClipOperation<Origin: Sendable>: Sendable {
  fileprivate let identity = UUID()
  public let entryID: String
  public let origin: Origin
}

public struct ClipOperationSlot<Origin: Sendable>: Sendable {
  public private(set) var current: ClipOperation<Origin>?

  public init() {}

  public mutating func begin(entryID: String, origin: Origin) -> ClipOperation<Origin> {
    let operation = ClipOperation(entryID: entryID, origin: origin)
    current = operation
    return operation
  }

  public func contains(_ operation: ClipOperation<Origin>) -> Bool {
    current?.identity == operation.identity
  }

  public mutating func invalidate() { current = nil }
}
