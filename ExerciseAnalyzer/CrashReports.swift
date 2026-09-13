// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Crash reports without a service: MetricKit hands the app its own crash and hang diagnostics on the next launch
//  (immediately in development builds). Each payload is written as JSON under Documents/crashes/ and announced in
//  the session log as `crash_report`, so `just pull-logs` brings the stack trees back with the logs. Frames are
//  addresses plus binary UUIDs; `just symbolicate <file>` resolves them with the build's dSYM.

import Darwin
import Foundation
import MetricKit

/// Last-resort crash log: a signal handler that writes the crashing thread's backtrace to
/// Documents/crashes/signal-<epoch>.txt with async-signal-safe calls only, for the runs where MetricKit has not
/// delivered a diagnostic yet (it does so on a later launch, sometimes much later for development builds).
private var crashFolderPath = [CChar](repeating: 0, count: 1024)

private func writeAll(_ fd: Int32, _ text: String) {
  text.utf8CString.withUnsafeBufferPointer { buffer in
    _ = write(fd, buffer.baseAddress, buffer.count - 1)
  }
}

private func crashSignalHandler(_ signal: Int32) {
  var path = crashFolderPath
  let name = "/signal-\(Int(time(nil))).txt"
  name.utf8CString.withUnsafeBufferPointer { src in
    let base = strlen(path)
    guard base + src.count < path.count else { return }
    for i in 0..<src.count { path[base + i] = src[i] }
  }
  let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
  guard fd >= 0 else { _exit(128 + signal) }
  writeAll(fd, "signal \(signal)\n")
  var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 128)
  let count = backtrace(&frames, Int32(frames.count))
  backtrace_symbols_fd(&frames, count, fd)
  close(fd)
  Darwin.signal(signal, SIG_DFL)
  raise(signal)
}

final class CrashReports: NSObject, MXMetricManagerSubscriber {
  static let shared = CrashReports()
  var onEvent: ((String, [String: Any]) -> Void)?

  static var folder: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("crashes", isDirectory: true)
  }

  func install() {
    MXMetricManager.shared.add(self)
    try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
    let path = Self.folder.path
    path.utf8CString.withUnsafeBufferPointer { src in
      for i in 0..<min(src.count, crashFolderPath.count - 64) { crashFolderPath[i] = src[i] }
    }
    for sig in [SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGTRAP, SIGFPE] { signal(sig, crashSignalHandler) }
  }

  /// Signal logs from earlier runs, announced once in this session's log and then renamed so they are not repeated.
  func reportSignalLogs(_ log: (String, [String: Any]) -> Void) {
    let files = (try? FileManager.default.contentsOfDirectory(atPath: Self.folder.path)) ?? []
    for name in files where name.hasPrefix("signal-") && name.hasSuffix(".txt") {
      let url = Self.folder.appendingPathComponent(name)
      let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
      let top = text.split(separator: "\n").prefix(12).joined(separator: " | ")
      log("crash_report", ["kind": "signal", "file": "crashes/\(name)", "top": top])
      try? FileManager.default.moveItem(at: url, to: Self.folder.appendingPathComponent(name.replacingOccurrences(of: ".txt", with: ".reported.txt")))
    }
  }

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
