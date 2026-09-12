// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Shake to report: a shake (or the Open menu's "Report a problem") opens a note sheet. Sending writes a
//  `bug_report` event into the session log with the current context, and appends a line to Documents/bugs.jsonl
//  that names the log file, so a developer session can jump from the report straight to the detailed log.

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
        ToolbarItem(placement: .confirmationAction) {
          Button("Log it") {
            session.reportBug(note: note)
            dismiss()
          }
          .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
      .onAppear { noteFocused = true }
    }
  }
}
