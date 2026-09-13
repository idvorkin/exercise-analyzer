// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Session-log retention: at launch the app deletes Documents/logs/*.jsonl older than 30 days, except any file
//  named by a report in Documents/bugs.jsonl (#72). The decision is pure — file names, ages and the referenced
//  set in, names to delete out — so the host covers it; the app supplies ages from modification dates and deletes.

public enum LogRetention {
  public static let retentionSeconds: Double = 30 * 24 * 3600

  /// Names to delete: older than `retention` seconds and not named by a bug report. Boundary stays (strictly older).
  public static func prune(
    files: [(name: String, age: Double)], referenced: Set<String>, retention: Double = retentionSeconds
  ) -> [String] {
    files.filter { $0.age > retention && !referenced.contains($0.name) }.map { $0.name }
  }
}
