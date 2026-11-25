// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Settings (story 088, #392; Igor, 2026-11-25: "let's have a high-level settings button from the main menu"): the
//  app's switches, one tap from Workouts by the gear beside ⋯, where they used to hide at the bottom of the
//  recording screen's exercise menu. "Send workouts to Larry" says under it whether sending is working.

import ExerciseCore
import SwiftUI

struct SettingsView: View {
  let session: VideoPoseSession
  private var sender: CockpitWorkoutSender { CockpitWorkoutSender.shared }
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Toggle(
            isOn: Binding(
              get: { sender.enabled },
              set: { on in
                session.log.event("settings", ["item": "send_to_larry", "on": on])
                sender.enabled = on
              })
          ) {
            Label("Send workouts to Larry", systemImage: "antenna.radiowaves.left.and.right")
          }
          // Re-read every 30 s, so "4 min ago" moves while the sheet is up.
          TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 4) {
              Text(sender.status.line(enabled: sender.enabled, waiting: sender.waiting, now: context.date))
                .font(.subheadline).foregroundStyle(.secondary)
                .accessibilityIdentifier("larryStatus")
              if sender.enabled, let problem = sender.status.problem {
                Text(problem).font(.footnote).foregroundStyle(.orange).textSelection(.enabled)
              }
            }
          }
        } footer: {
          Text(
            "Each workout's heart rate, sets and weights go to Larry's Cockpit as you train, and any it is missing afterwards."
          )
        }
        Section {
          Toggle(
            isOn: Binding(
              get: { session.bellDetectorOn },
              set: { on in
                session.log.event("settings", ["item": "bell_detector", "on": on])
                session.setBellDetector(on)
              })
          ) {
            Label("Bell detector (slower pass)", systemImage: "circle.circle")
          }
        } footer: {
          Text(
            "Finds the bell on a swing or get-up for its dot and colour; the pass over a video takes about twice as long."
          )
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
  }
}
