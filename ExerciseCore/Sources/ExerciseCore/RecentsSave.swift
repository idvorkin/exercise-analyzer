import Foundation

/// Synchronous, single-writer transaction. The app calls this on the main actor, without awaits.
/// The index rename is the commit point. A journal permits rollback after termination between folder moves.
/// Existing index rows and set folders retain their format; temporary files are siblings under the root.
public struct RecentsSave {
  public enum Stage: CaseIterable { case prepared, staged, oldMoved, installed, indexWritten }
  private struct Journal: Codable {
    var id: String
    var hadDestination: Bool
    var retired: [String]
    var index: Data
  }
  private static let transactionName = ".recents-save"

  /// `entry` starts from the existing value so metadata outside the analysis stays intact.
  /// The writer receives a private copy of the old folder (including Undo trim and auxiliary files).
  public static func save(
    root: URL, index: RecentsIndex, id: String, source: RecentEntry.Source,
    makeEntry: (RecentEntry?) throws -> RecentEntry,
    writeFiles: (URL) throws -> Void,
    checkpoint: (Stage) throws -> Void = { _ in }
  ) throws -> RecentsIndex {
    try recover(root: root)
    let fm = FileManager.default
    let matching = index.entries.filter { $0.id == id || $0.isSameClip(source: source, originalName: nil, duration: 0) }
    let existing = matching.first { $0.id == id } ?? matching.first
    var entry = try makeEntry(existing)
    precondition(entry.id == id)
    // Recovery distinguishes the committed index by its bytes, even for an otherwise identical re-save.
    if let existing, entry.analyzedAt <= existing.analyzedAt {
      entry.analyzedAt = existing.analyzedAt.addingTimeInterval(0.001)
    }
    let next = RecentsIndex(entries: [entry] + index.entries.filter { old in !matching.contains { $0.id == old.id } })
    let transaction = root.appendingPathComponent(transactionName, isDirectory: true)
    let staged = transaction.appendingPathComponent("staged", isDirectory: true)
    let destination = root.appendingPathComponent(id, isDirectory: true)
    let journal = Journal(id: id, hadDestination: fm.fileExists(atPath: destination.path),
      retired: matching.map(\.id).filter { $0 != id }, index: try JSONEncoder().encode(next.entries))
    try fm.createDirectory(at: transaction, withIntermediateDirectories: true)
    do {
      try JSONEncoder().encode(journal).write(to: transaction.appendingPathComponent("journal.json"), options: .atomic)
      try checkpoint(.prepared)
      if let existing {
        try fm.copyItem(at: root.appendingPathComponent(existing.id), to: staged)
      } else {
        try fm.createDirectory(at: staged, withIntermediateDirectories: true)
      }
      try writeFiles(staged)
      try checkpoint(.staged)
      if journal.hadDestination {
        try fm.moveItem(at: destination, to: transaction.appendingPathComponent("old"))
      }
      try checkpoint(.oldMoved)
      try fm.moveItem(at: staged, to: destination)
      try checkpoint(.installed)
      try journal.index.write(to: root.appendingPathComponent("index.json"), options: .atomic)
    } catch {
      try recover(root: root)
      throw error
    }
    // After the commit point, cleanup failure cannot turn a successful save into a reported failure.
    // Leave the journal for the next launch/save to finish retiring the old files.
    do {
      try checkpoint(.indexWritten)
      try recover(root: root)
    } catch {}
    return next
  }

  public static func recover(root: URL) throws {
    let fm = FileManager.default
    let transaction = root.appendingPathComponent(transactionName, isDirectory: true)
    guard fm.fileExists(atPath: transaction.path) else { return }
    let journalURL = transaction.appendingPathComponent("journal.json")
    guard fm.fileExists(atPath: journalURL.path) else {
      try fm.removeItem(at: transaction) // No journal means no destination mutation was started.
      return
    }
    let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
    let destination = root.appendingPathComponent(journal.id)
    let old = transaction.appendingPathComponent("old")
    let committed = (try? Data(contentsOf: root.appendingPathComponent("index.json"))) == journal.index
    if committed {
      for id in journal.retired {
        let url = root.appendingPathComponent(id)
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
      }
    } else if fm.fileExists(atPath: old.path) {
      if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
      try fm.moveItem(at: old, to: destination)
    } else if !journal.hadDestination && !fm.fileExists(atPath: transaction.appendingPathComponent("staged").path) {
      if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
    }
    try fm.removeItem(at: transaction)
  }
}
