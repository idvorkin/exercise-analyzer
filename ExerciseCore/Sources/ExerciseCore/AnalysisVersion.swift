// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Bump this whenever an analyzer, the detector, or the skeleton math changes. Stored analyses carry the version
//  they were made with; the app re-analyzes any set whose version is older (issue #19), so a fix lands on old
//  sets too instead of leaving stale counts in the gallery.

public enum AnalysisVersion {
  // 2026-09-18.1: a hole in the track ends the swing in progress and counting restarts at the next top (#94).
  // 2026-09-18.2: a swing's top may be as low as 32° on a fast upswing (one-arm swings with the upper arm on the
  // ribs), and needs the hip past 160° (was 150°: standing up from the bell park is not a top) (#97).
  // 2026-09-19.1: pull-ups, and the detector asks about hands held over the shoulders (#108).
  // 2026-09-19.2: split squats, and the detector asks about feet split with the hips low (#112).
  // 2026-09-19.3: a split squat rep also ends when the hips top out under the standing height (a static split
  // after standing tall) (#112).
  public static let current = "2026-09-19.3"
}
