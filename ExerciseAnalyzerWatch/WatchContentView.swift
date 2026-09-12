// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import ExerciseCore
import SwiftUI

struct WatchContentView: View {
  @ObservedObject var phone: PhoneLink
  /// Ticks so a status that stops arriving turns stale on screen.
  @State private var now = Date()
  private let clock = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

  private var status: WatchStatus { phone.status }

  var body: some View {
    ScrollView {
      VStack(spacing: 8) {
        if !phone.isLive {
          Image(systemName: "iphone.slash").font(.largeTitle).foregroundStyle(.secondary)
          Text(phone.reachable ? "Waiting for the phone app…" : "Phone not reachable. Open Exercise Analyzer on the phone.")
            .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
          Button { phone.ping() } label: { Label("Retry", systemImage: "arrow.clockwise").frame(maxWidth: .infinity) }
        } else if status.recording {
          Text(status.frame.hint.uppercased())
            .font(.headline).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(status.frame.inFrame ? Color.green.opacity(0.35) : Color.red.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
          HStack {
            VStack {
              Text("\(status.reps)").font(.system(size: 34, weight: .bold, design: .rounded))
              Text("reps").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            VStack {
              Text(elapsed).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
              Text(status.camera == "front" ? "front cam" : "back cam").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
          }
          if !status.exercise.isEmpty {
            Text(status.exercise).font(.caption2).foregroundStyle(.secondary)
          }
          Button { phone.send(.switchCamera) } label: {
            Label("Switch camera", systemImage: "arrow.triangle.2.circlepath.camera").frame(maxWidth: .infinity)
          }
          Button { phone.send(.finish) } label: {
            Label("Done", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
          }
          .tint(.green)
          Button(role: .destructive) { phone.send(.cancel) } label: {
            Label("Cancel", systemImage: "xmark.circle").frame(maxWidth: .infinity)
          }
        } else {
          Image(systemName: "figure.strengthtraining.traditional").font(.largeTitle).foregroundStyle(.secondary)
          Text(phone.reachable ? "Phone ready" : "Open Exercise Analyzer on the phone")
            .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
          Button { phone.send(.start) } label: {
            Label("Record", systemImage: "record.circle").frame(maxWidth: .infinity)
          }
          .tint(.red)
          .disabled(!phone.reachable)
        }
        if let error = phone.lastError {
          Text(error).font(.caption2).foregroundStyle(.red).multilineTextAlignment(.center)
        }
      }
      .padding(.horizontal, 4)
    }
    .onReceive(clock) { now = $0; if !phone.isLive { phone.ping() } }
    .onAppear { phone.ping() }
  }

  private var elapsed: String {
    let total = Int(status.elapsed)
    return String(format: "%d:%02d", total / 60, total % 60)
  }
}
