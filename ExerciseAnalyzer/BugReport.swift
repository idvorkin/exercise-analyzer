// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Shake to report, through BugKit (https://github.com/idvorkin/bug-kit): a shake, the Open menu's "Report a
//  problem" or ⌘I opens BugKit's sheet over whatever is up; "Log it" writes a `bug_report` event into the session
//  log and one line into Documents/bugs.jsonl (locked append, a unique folder per report) with the screenshot and,
//  in playback, the clip's frame at the playhead. This file is Exercise Analyzer's side: what a report carries.

import AVFoundation
import BugKit
import Combine
import ExerciseCore
import UIKit

extension VideoPoseSession {
  /// This session's log as BugKit's logger: its events (bug_report, crash_report, logs_pruned, error…) land beside
  /// everything else the app did. `JSONValue.foundation` is BugKit's bridge to `[String: Any]` (bug-kit PR #4).
  var bugLogger: BugLogger {
    let log = log
    return { type, fields in log.event(type, fields.mapValues(\.foundation)) }
  }

  /// One reporter for the app, made on first use (the hooks read this session's state, so it cannot exist before it).
  func makeBugReporter() -> BugReporter {
    var options = BugReporterOptions()
    options.another = .keepMoment  // #212: every report from one sheet is about the shake's moment
    options.gentleShake = false  // a phone carried between sets flicks; iOS's own shake is the report gesture here
    options.launchHookPrefix = "SWING"  // SWING_BUG="a|b", SWING_SHAKE_AFTER=8 in the simulator checks
    options.placeholder = "e.g. counted 1 rep, there were 13"
    // #250: the mic button on the sheet (the usage strings are in the project's INFOPLIST_KEYs). Nothing of ours
    // holds the microphone (the camera captures video only), so the busy hook stays BugKit's default.
    options.dictation = true
    let log = log
    let store = BugStore()
    let reporter = BugReporter(
      hooks: BugReporterHooks(
        screen: { [unowned self] in self.bugScreen },
        context: { [unowned self] in
          // The moment of the shake: the frame comes from the clip and playhead as they were when the sheet opened.
          self.bugClip = self.source == .camera ? nil : self.currentFileURL.map { ($0, self.currentTime) }
          return self.bugContext()
        },
        sessionLog: { ("logs/\(log.url.lastPathComponent)", Int(Date().timeIntervalSince(log.startedAt) * 1000)) },
        logger: bugLogger,
        extraFiles: { [weak self] folder in
          guard let clip = await MainActor.run(body: { self?.bugClip }) else { return [] }
          return try await Self.writeFrame(of: clip, into: folder)
        }), options: options, store: store, delivery: makeBugDelivery(store: store))
    bugStatus = reporter.$lastStatus.compactMap { $0 }.sink { [weak self] in self?.noteBugStatus($0) }
    return reporter
  }

  /// Private CloudKit delivery of every report (bug-kit's `CloudKitReportDelivery`, story 022): the phone uploads
  /// the report and its files to the container every app shares, and the Mac's listener downloads and files them,
  /// so a shake in the gym becomes an issue without the phone ever meeting the Mac. The report is saved locally
  /// first, so the device pull keeps working when the upload cannot. `start()` runs here and on every return to
  /// the foreground: it resumes the outbox after a kill and queues what was saved while offline. Off in the
  /// simulator, which has no iCloud account: the retries would only fill the smoke checks' logs.
  private func makeBugDelivery(store: BugStore) -> CloudKitReportDelivery? {
    #if targetEnvironment(simulator)
      return nil
    #else
      let delivery = CloudKitReportDelivery(
        containerIdentifier: Self.bugReportsContainer, store: store, logger: bugLogger)
      Task {
        await delivery.start()
        // The reporter lives as long as the app, so this loop does too; nothing to retain or cancel.
        for await _ in NotificationCenter.default.notifications(named: UIApplication.willEnterForegroundNotification) {
          await delivery.start()
        }
      }
      return delivery
    #endif
  }

  /// The CloudKit container the bug-kit apps and the Mac reader share (the listener's `~/.config/bug-kit/cloudkit.json`
  /// names the same one); also in the entitlements, next to the app's own iCloud Documents container.
  static let bugReportsContainer = "iCloud.com.idvorkin.BugKitReports"

  /// What a report carries besides the note (story 022): enough to find the moment in the log and the clip in
  /// Workouts. Numbers stay numbers, so `jq` can compare them.
  func bugContext() -> [String: JSONValue] {
    var context: [String: JSONValue] = [
      "exercise": .string(exercise.definition.name),
      "mode": .string(exerciseMode.storageValue),
      "source": .string("\(source)"),
      "playhead": .double((currentTime * 100).rounded() / 100),
      "reps": .int(reps.count),
      "phase": .string(latestFrame?.analysis?.phase ?? "–"),
    ]
    if let id = currentEntryID { context["recents_id"] = .string(id) }
    if let url = trimmedURL ?? currentFileURL { context["clip"] = .string(url.lastPathComponent) }
    if let detection {
      context["detected"] = .string(detection.exercise.rawValue)
      context["detected_confidence"] = .int(detection.confidence)
    }
    return context
  }

  /// The clip's frame at the playhead, as `frame.jpg` in the report's folder (story 026, #24): what the lifter was
  /// looking at, since the window snapshot can show the video layer black.
  private static func writeFrame(of clip: (url: URL, time: Double), into folder: URL) async throws -> [String] {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: clip.url))
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 720, height: 720)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let (image, _) = try await generator.image(at: CMTime(seconds: clip.time, preferredTimescale: 600))
    guard let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.8) else { return [] }
    try data.write(to: folder.appendingPathComponent("frame.jpg"))
    return ["frame.jpg"]
  }
}
