// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Live heart rate started and ended from outside the app (story 092, context-grabber-at59): the Shortcuts actions
//  "Start live heart rate" and "End live heart rate", run without bringing the app forward, and the link
//  `exerciseanalyzer://live-heart-rate/start?kind=call` (or `/end`) another app opens, which does bring it forward
//  and goes back by `x-success` / `x-error`. No app can run another app's action itself, so Grabber takes the link.

import AppIntents
import ExerciseCore
import UIKit

enum LiveHeartRateKind: String, AppEnum {
  case call, walk

  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Kind"
  static var caseDisplayRepresentations: [LiveHeartRateKind: DisplayRepresentation] = [
    .call: "Call", .walk: "Walk",
  ]

  var kind: WorkoutKind { self == .call ? .call : .walk }
}

/// Why the watch did not start or end it, as the shortcut shows it.
struct LiveHeartRateFailure: Error, CustomLocalizedStringResourceConvertible {
  let reason: String
  var localizedStringResource: LocalizedStringResource { "\(reason)" }
}

struct StartLiveHeartRateIntent: AppIntent {
  static var title: LocalizedStringResource = "Start live heart rate"
  static var description = IntentDescription(
    "Starts Live heart rate on the watch: a call or a walk whose heart rate goes to Larry. Empty Kind lets the watch choose, as a tap on Live does."
  )
  static var openAppWhenRun = false

  @Parameter(title: "Kind")
  var kind: LiveHeartRateKind?

  @MainActor
  func perform() async throws -> some IntentResult {
    if let reason = await WorkoutMirror.shared.startLiveOnWatch(kind: kind?.kind, from: "shortcut") {
      throw LiveHeartRateFailure(reason: reason)
    }
    return .result()
  }
}

struct EndLiveHeartRateIntent: AppIntent {
  static var title: LocalizedStringResource = "End live heart rate"
  static var description = IntentDescription(
    "Ends the watch's Live heart rate call or walk, as its End does. A gym workout is never ended."
  )
  static var openAppWhenRun = false

  @MainActor
  func perform() async throws -> some IntentResult {
    if let reason = await WorkoutMirror.shared.endLiveOnWatch(from: "shortcut") {
      throw LiveHeartRateFailure(reason: reason)
    }
    return .result()
  }
}

enum LiveHeartRateLink {
  /// Takes `exerciseanalyzer://live-heart-rate/…`; false for any other link. The caller goes back by its
  /// `x-success`, or `x-error` with the reason, once the watch has been asked.
  @MainActor
  static func open(_ url: URL) -> Bool {
    guard let request = LiveLaunch.Request(url: url) else { return false }
    Task { @MainActor in
      let failure: String?
      switch request.action {
      case .start(let kind): failure = await WorkoutMirror.shared.startLiveOnWatch(kind: kind, from: "link")
      case .end: failure = await WorkoutMirror.shared.endLiveOnWatch(from: "link")
      }
      if let back = request.back(error: failure) { await UIApplication.shared.open(back) }
    }
    return true
  }
}
