// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Crash reports without a service: MetricKit hands the app its own crash and hang diagnostics on the next launch
//  (immediately in development builds). Each payload is written as JSON under Documents/crashes/ and announced in
//  the session log as `crash_report`, so `just pull-logs` brings the stack trees back with the logs. Frames are
//  addresses plus binary UUIDs; `just symbolicate <file>` resolves them with the build's dSYM.

import Foundation
import MetricKit

final class CrashReports: NSObject, MXMetricManagerSubscriber {
  static let shared = CrashReports()
  var onEvent: ((String, [String: Any]) -> Void)?

  static var folder: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("crashes", isDirectory: true)
  }

  func install() { MXMetricManager.shared.add(self) }

  func didReceive(_ payloads: [MXDiagnosticPayload]) {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
    for payload in payloads {
      let crashes = payload.crashDiagnostics ?? []
      let hangs = payload.hangDiagnostics ?? []
      guard !crashes.isEmpty || !hangs.isEmpty else { continue }
      let name = "\(formatter.string(from: payload.timeStampEnd)).json"
      try? payload.jsonRepresentation().write(to: Self.folder.appendingPathComponent(name))
      for crash in crashes {
        onEvent?(
          "crash_report",
          [
            "file": "crashes/\(name)", "kind": "crash",
            "exception": crash.exceptionType?.intValue ?? 0, "code": crash.exceptionCode?.intValue ?? 0,
            "signal": crash.signal?.intValue ?? 0, "reason": crash.terminationReason ?? "",
            "app": crash.applicationVersion, "ended": ISO8601DateFormatter().string(from: payload.timeStampEnd),
          ])
      }
      for hang in hangs {
        onEvent?("crash_report", ["file": "crashes/\(name)", "kind": "hang", "seconds": hang.hangDuration.value])
      }
    }
  }

  func didReceive(_ payloads: [MXMetricPayload]) {}
}
