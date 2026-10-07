// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Shake to report: a shake (or the Open menu's "Report a problem") opens a note sheet. Sending writes a
//  `bug_report` event into the session log with the current context, and appends a line to Documents/bugs.jsonl
//  that names the log file, so a developer session can jump from the report straight to the detailed log.

import AVFoundation
import ExerciseCore
import SwiftUI
import UIKit

/// Calls `onShake` when the device is shaken. Sits invisibly in the view tree and holds first responder.
struct ShakeDetector: UIViewControllerRepresentable {
  let onShake: () -> Void

  final class Controller: UIViewController {
    var onShake: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      becomeFirstResponder()
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
      if motion == .motionShake { onShake?() }
      super.motionEnded(motion, with: event)
    }
  }

  func makeUIViewController(context: Context) -> Controller {
    let controller = Controller()
    controller.onShake = onShake
    controller.view.isUserInteractionEnabled = false
    return controller
  }

  func updateUIViewController(_ controller: Controller, context: Context) {
    controller.onShake = onShake
  }
}

struct BugReportSheet: View {
  @ObservedObject var session: VideoPoseSession
  @Environment(\.dismiss) private var dismiss
  @State private var note = ""
  @FocusState private var noteFocused: Bool

  private var noteEmpty: Bool { note.trimmingCharacters(in: .whitespaces).isEmpty }

  var body: some View {
    NavigationStack {
      Form {
        Section("What went wrong?") {
          TextField("e.g. counted 1 rep, there were 13", text: $note, axis: .vertical)
            .lineLimit(3...8)
            .focused($noteFocused)
        }
        Section("Attached automatically") {
          ForEach(session.bugContext().sorted(by: { $0.key < $1.key }), id: \.key) { item in
            LabeledContent(item.key, value: item.value)
          }
        }
      }
      .navigationTitle("Report a problem")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItemGroup(placement: .confirmationAction) {
          // #212: the next bug without another shake. The report is saved as Log it saves it, with the shake's
          // screenshot and frame (BugReporter keeps them until the next shake), and the sheet empties for the next.
          Button("Log it and another") {
            session.reportBug(note: note)
            note = ""
            noteFocused = true
          }
          .disabled(noteEmpty)
          Button("Log it") {
            session.reportBug(note: note)
            dismiss()
          }
          .disabled(noteEmpty)
        }
      }
      .onAppear { noteFocused = true }
    }
  }
}

/// The report's files: what the screen showed at the shake, the line in bugs.jsonl and the session log, and the
/// pruning of old logs no report names (#24, #72). Out of VideoPoseSession (the architecture decision's step 5,
/// #171); the session supplies the context, since that is its state.
@MainActor
final class BugReporter {
  private let log: SessionLog
  private let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
  /// What the screen showed when the shake landed: a snapshot of the window (HUD, pills, gallery; video layers
  /// may come out black) and, in playback, the clip's own frame at the playhead. Saved with the report (#24).
  private var screenshot: UIImage?
  private var frame: CGImage?

  init(log: SessionLog) { self.log = log }

  /// `clip`: the file and playhead while playing one back; nil on the camera, which has no file to read a frame from.
  func capture(clip: (url: URL, time: Double)?) {
    let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
    if let window = windows.first(where: \.isKeyWindow) ?? windows.first {
      screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
      }
    }
    frame = nil
    guard let clip else { return }
    let time = CMTime(seconds: clip.time, preferredTimescale: 600)
    Task { [weak self] in
      let generator = AVAssetImageGenerator(asset: AVURLAsset(url: clip.url))
      generator.appliesPreferredTrackTransform = true
      generator.maximumSize = CGSize(width: 720, height: 720)
      generator.requestedTimeToleranceBefore = .zero
      generator.requestedTimeToleranceAfter = .zero
      if let (image, _) = try? await generator.image(at: time) { self?.frame = image }
    }
  }

  private static let folderFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyyMMdd-HHmmss"
    return f
  }()

  /// Writes the captured screenshot and frame under Documents/bugs/<stamp>/ and returns their relative paths. The
  /// images stay until the next `capture`: a report that follows from the same sheet ("Log it and another", #212)
  /// is about the same moment and carries them too.
  private func saveImages(stamp: String) -> [String: String] {
    var saved: [String: String] = [:]
    let folder = documents.appendingPathComponent("bugs", isDirectory: true).appendingPathComponent(stamp, isDirectory: true)
    let files: [(String, Data?, String)] = [
      ("screen.png", screenshot?.pngData(), "screenshot"),
      ("frame.jpg", frame.map { UIImage(cgImage: $0).jpegData(compressionQuality: 0.8) } ?? nil, "frame"),
    ]
    for (name, data, key) in files {
      guard let data else { continue }
      do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(name))
        saved[key] = "bugs/\(stamp)/\(name)"
      } catch {
        log.event("error", ["where": "bug_images", "message": "\(error)"])
      }
    }
    return saved
  }

  /// Writes the report into the session log and to Documents/bugs.jsonl (one line per report, newest last), and
  /// returns what the status line says.
  func report(note: String, context: [String: String]) -> String {
    let now = Date()
    let images = saveImages(stamp: Self.folderFormatter.string(from: now))
    let context = context.merging(images) { a, _ in a }
    log.event("bug_report", context.merging(["note": note]) { a, _ in a })
    var record: [String: Any] = context
    record["note"] = note
    record["reported_at"] = ISO8601DateFormatter().string(from: now)
    record["session_t_ms"] = Int(Date().timeIntervalSince(log.startedAt) * 1000)
    let url = documents.appendingPathComponent("bugs.jsonl")
    do {
      let line = try JSONSerialization.data(withJSONObject: record) + Data([0x0A])
      if let handle = try? FileHandle(forWritingTo: url) {
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(line)
      } else {
        try line.write(to: url)
      }
      return "Problem logged. Thanks."
    } catch {
      // The report is in the session log either way; bugs.jsonl is what `just file-bugs` reads, so say it is missing.
      log.event("error", ["where": "bug_report", "message": "\(error)"])
      return "Problem noted in the log; bugs.jsonl could not be written"
    }
  }

  /// Deletes session logs older than 30 days, except any named by a report in bugs.jsonl (#72). Runs at launch,
  /// after the new session's log is open, and logs one `logs_pruned` event even when zero. A file whose age
  /// cannot be read is never deleted.
  func pruneOldLogs() {
    let dir = documents.appendingPathComponent("logs", isDirectory: true)
    let now = Date()
    // A bugs.jsonl that exists but cannot be read means the reported logs are unknown: prune nothing rather
    // than delete evidence (the 2026-09-15 review).
    guard let referenced = Self.referencedLogs(at: documents.appendingPathComponent("bugs.jsonl")) else {
      log.event("error", ["where": "logs_prune", "message": "bugs.jsonl unreadable; nothing pruned"])
      return
    }
    let files = ((try? FileManager.default.contentsOfDirectory(
      at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? [])
      .filter { $0.pathExtension == "jsonl" }
      .compactMap { url -> (name: String, age: Double, size: Int)? in
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
          let modified = values.contentModificationDate
        else { return nil }
        return (url.lastPathComponent, now.timeIntervalSince(modified), values.fileSize ?? 0)
      }
    let victims = Set(LogRetention.prune(
      files: files.map { (name: $0.name, age: $0.age) }, referenced: referenced))
    var count = 0, freed = 0
    for file in files where victims.contains(file.name) {
      do {
        try FileManager.default.removeItem(at: dir.appendingPathComponent(file.name))
        count += 1
        freed += file.size
      } catch {
        log.event("error", ["where": "logs_prune", "file": file.name, "message": "\(error)"])
      }
    }
    let kept = files.filter { $0.age > LogRetention.retentionSeconds && referenced.contains($0.name) }.count
    log.event("logs_pruned", ["count": count, "bytes": freed, "kept_for_reports": kept])
  }

  /// The session logs bug reports name; nil when bugs.jsonl exists but cannot be read (no file: empty set).
  /// Malformed lines are skipped.
  private static func referencedLogs(at url: URL) -> Set<String>? {
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return nil }
    var names = Set<String>()
    for line in text.split(separator: "\n") {
      guard let lineData = line.data(using: .utf8),
        let record = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
        let name = record["log"] as? String
      else { continue }
      names.insert(name)
    }
    return names
  }
}
