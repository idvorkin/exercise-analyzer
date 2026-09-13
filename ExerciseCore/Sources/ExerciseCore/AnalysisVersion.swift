// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Bump this whenever an analyzer, the detector, or the skeleton math changes. Stored analyses carry the version
//  they were made with; the app re-analyzes any set whose version is older (issue #19), so a fix lands on old
//  sets too instead of leaving stale counts in the gallery.

public enum AnalysisVersion {
  public static let current = "2026-09-12.7"
}
