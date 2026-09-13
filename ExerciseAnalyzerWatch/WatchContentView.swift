// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import ExerciseCore
import SwiftUI

struct WatchContentView: View {
  @ObservedObject var phone: PhoneLink
  @Environment(\.scenePhase) private var scenePhase
  /// Ticks so a status that stops arriving turns stale on screen.
  @State private var now = Date()
  private let clock = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

  private var status: WatchStatus { phone.status }

  var body: some View {
    ScrollView {
      VStack(spacing: 8) {
        if !phone.isLive {
          Image(systemName: "iphone.slash").font(.largeTitle).foregroundStyle(.secondary)
          Text(phone.reachable ? "Waiting for the phone…" : "Not connected to the phone. It reconnects on its own; if it doesn't, open Exercise Analyzer on the phone.")
            .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
          if status.recording {
            Text("Last seen recording: \(status.reps) reps").font(.caption2).foregroundStyle(.tertiary)
          }
          if let since = phone.receivedAt {
            // Reconnects by itself (retries every 2 s); this just says how long it has been.
            Text("Last heard \(Int(max(0, now.timeIntervalSince(since)))) s ago").font(.caption2).foregroundStyle(.tertiary)
          }
          Button { phone.ping() } label: { Label("Retry", systemImage: "arrow.clockwise").frame(maxWidth: .infinity) }
        } else if !status.phoneActive {
          Image(systemName: "iphone.gen3").font(.largeTitle).foregroundStyle(.secondary)
          Text("The phone app is in the background. Unlock the phone and open Exercise Analyzer; it stays awake while the watch is connected.")
            .font(.caption2).multilineTextAlignment(.center).foregroundStyle(.secondary)
          Button { phone.send(.start) } label: {
            Label("Send a reminder to the phone", systemImage: "bell").frame(maxWidth: .infinity)
          }
        } else if status.recording {
          if let preview = phone.preview {
            Image(uiImage: preview).resizable().scaledToFit()
              .frame(maxWidth: .infinity, maxHeight: 90)
              .clipShape(RoundedRectangle(cornerRadius: 8))
          }
          Text(status.paused ? "PAUSED · \(status.frame.hint.uppercased())" : status.frame.hint.uppercased())
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
              Text(cameraLevel).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
          }
          if !status.exercise.isEmpty {
            Text(status.exercise).font(.caption2).foregroundStyle(.secondary)
          }
          Button { phone.send(.switchCamera) } label: {
            Label("Camera: \(cameraLevel)", systemImage: "arrow.triangle.2.circlepath.camera").frame(maxWidth: .infinity)
          }
          Button { phone.send(status.paused ? .resume : .pause) } label: {
            Label(status.paused ? "Resume" : "Pause", systemImage: status.paused ? "play.fill" : "pause.fill").frame(maxWidth: .infinity)
          }
          .tint(status.paused ? .orange : nil)
          Button { phone.send(.finish) } label: {
            Label("Done", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
          }
          .tint(.green)
          Button(role: .destructive) { phone.send(.cancel) } label: {
            Label("Cancel", systemImage: "xmark.circle").frame(maxWidth: .infinity)
          }
          watchModeToggle
        } else {
          Image(systemName: "figure.strengthtraining.traditional").font(.largeTitle).foregroundStyle(.secondary)
          Text(phone.reachable ? "Phone ready" : "Open Exercise Analyzer on the phone")
            .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
          Button { phone.send(.start) } label: {
            Label("Record", systemImage: "record.circle").frame(maxWidth: .infinity)
          }
          .tint(.red)
          .disabled(!phone.reachable)
          exercisePicker
        }
        if let error = phone.lastError {
          Text(error).font(.caption2).foregroundStyle(.red).multilineTextAlignment(.center)
        }
      }
      .padding(.horizontal, 4)
    }
    .onReceive(clock) { now = $0; if !phone.isLive { phone.ping() } }
    .onAppear { phone.sceneActive(true) }  // also pings; the phone learns the app is in front even without a scene change
    .onChange(of: scenePhase) { _, phase in phone.sceneActive(phase == .active) }
  }

  /// Watch mode on the phone: big digits on its screen, everything driven from here. Only while recording: the
  /// phone refuses it otherwise (#36).
  private var watchModeToggle: some View {
    Button { phone.send(.watchMode) } label: {
      Label(status.watchMode ? "Phone: watch mode on" : "Phone: watch mode", systemImage: status.watchMode ? "iphone.gen3.radiowaves.left.and.right" : "iphone.gen3")
        .frame(maxWidth: .infinity)
    }
    .tint(status.watchMode ? .blue : nil)
  }

  /// Auto or a specific exercise; the phone re-analyzes and reports back through `mode`.
  private var exercisePicker: some View {
    let options: [(String, String)] = [("auto", "Auto")] + ExerciseKind.allCases.map { ($0.rawValue, $0.definition.name) }
    return Picker("Exercise", selection: Binding(get: { status.mode }, set: { phone.pick(exercise: $0) })) {
      ForEach(options, id: \.0) { option in Text(option.1).tag(option.0) }
    }
    .pickerStyle(.navigationLink)
  }

  /// "Front", "0.5×" or "1×": the three views that matter, cycled by one button.
  private var cameraLevel: String {
    if status.camera == "front" { return "Front" }
    return status.zoom < 1 ? "0.5×" : "1×"
  }

  private var elapsed: String {
    let total = Int(status.elapsed)
    return String(format: "%d:%02d", total / 60, total % 60)
  }
}
