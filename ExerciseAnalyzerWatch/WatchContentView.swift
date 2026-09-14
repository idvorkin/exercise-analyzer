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
    Group {
      // The picture page whenever the camera is live: `recording` means the camera is up. `phoneActive` is the
      // follow-the-wrist decision (041), never a gate on the picture (2026-09-13 regression: the wrist dropped to
      // the idle pages whenever the phone app was not .active, and lost its framing controls with it).
      if phone.isLive && status.recording {
        recordingPages
      } else {
        idlePages
      }
    }
    .onReceive(clock) { now = $0; if !phone.isLive { phone.ping() } }
    .onAppear { phone.sceneActive(true) }  // also pings; the phone learns the app is in front even without a scene change
    .onChange(of: scenePhase) { _, phase in phone.sceneActive(phase == .active) }
  }

  /// Everything that is not a recording: the not-connected, backgrounded-phone and idle screens, unchanged.
  private var idlePages: some View {
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
        } else {
          Image(systemName: "figure.strengthtraining.traditional").font(.largeTitle).foregroundStyle(.secondary)
          Text(phone.reachable ? "Phone ready" : "Open Exercise Analyzer on the phone")
            .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
          // The offline pass's final count (045): "Analyzing…" while it runs, then the last set's line. The
          // next recording status carries neither and the line goes.
          if status.phase == "analyzing" {
            Text("Analyzing…").font(.caption).foregroundStyle(.secondary)
          } else if let last = status.lastSet {
            Text("Last set").font(.caption2).foregroundStyle(.secondary)
            Text("\(last.reps) reps · \(last.exercise) · \(Self.duration(last.seconds))")
              .font(.headline).monospacedDigit()
          }
          Button { phone.send(.start) } label: {
            Label("Record", systemImage: "record.circle").frame(maxWidth: .infinity)
          }
          .tint(.red)
          .disabled(!phone.reachable)
          restStatus
          restPicker
          exercisePicker
        }
        if let error = phone.lastError {
          Text(error).font(.caption2).foregroundStyle(.red).multilineTextAlignment(.center)
        }
      }
      .padding(.horizontal, 4)
    }
  }

  /// A set fills the watch: the picture edge to edge with the count, the time and the controls over it, and a
  /// second page for everything a stray touch must not reach (story 042). Taps still go through `phone.send`.
  private var recordingPages: some View {
    TabView {
      recordingPicturePage
      recordingControlsPage
    }
    .tabViewStyle(.verticalPage)
  }

  /// Page one: the preview filling the screen, chips over its top corners, the hint bar and the round buttons
  /// over its bottom edge. No picture yet: the same overlays on black. Only the picture ignores the safe area:
  /// the chips sit below the system clock line, and the button row lives in a bottom safeAreaInset lifted 20 pt,
  /// inset 16 pt from both sides with 40 pt buttons, so the bezel and the rounded corners keep nothing (refs #74).
  private var recordingPicturePage: some View {
    ZStack {
      if let preview = phone.preview {
        Image(uiImage: preview).resizable().scaledToFill()
          .ignoresSafeArea()
      } else {
        Color.black.ignoresSafeArea()
      }
      VStack(spacing: 6) {
        HStack {
          Text("\(status.reps)")
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .padding(.horizontal, 10).padding(.vertical, 2)
            .background(.ultraThinMaterial, in: Capsule())
          Spacer()
          Text(elapsed).monospacedDigit()
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.horizontal, 8)
        .padding(.top, 40)
        Spacer()
        Text(hintText)
          .font(.caption).multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 6)
          .background(status.frame.inFrame ? Color.green.opacity(0.5) : Color.red.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
          .padding(.horizontal, 8)
      }
      .safeAreaInset(edge: .bottom) {
        HStack(spacing: 14) {
          Button { phone.send(status.paused ? .resume : .pause) } label: {
            Image(systemName: status.paused ? "play.fill" : "pause.fill")
              .font(.body)
              .frame(width: 40, height: 40)
              .background(status.paused ? Color.orange : Color.gray.opacity(0.5), in: Circle())
              .foregroundStyle(.white)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(status.paused ? "Resume" : "Pause")
          Button { phone.send(.switchCamera) } label: {
            Text(cameraLevel)
              .font(.caption.bold())
              .minimumScaleFactor(0.5).lineLimit(1)
              .frame(width: 40, height: 40)
              .background(Color.gray.opacity(0.5), in: Circle())
              .foregroundStyle(.white)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Camera: \(cameraLevel)")
          Button { phone.send(.finish) } label: {
            Image(systemName: "checkmark")
              .font(.body.bold())
              .frame(width: 40, height: 40)
              .background(Color.green, in: Circle())
              .foregroundStyle(.white)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Done")
          Button { phone.send(.cancel) } label: {
            Image(systemName: "xmark")
              .font(.body.bold())
              .frame(width: 36, height: 36)
              .background(Color.red.opacity(0.7), in: Circle())
              .foregroundStyle(.white)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Cancel")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
      }
    }
  }

  /// Page two (swipe up): the exercise, Cancel, the watch-mode toggle and the last error, in the list style.
  private var recordingControlsPage: some View {
    ScrollView {
      VStack(spacing: 8) {
        if !status.exercise.isEmpty {
          Text(status.exercise).font(.caption2).foregroundStyle(.secondary)
        }
        Button(role: .destructive) { phone.send(.cancel) } label: {
          Label("Cancel", systemImage: "xmark.circle").frame(maxWidth: .infinity)
        }
        watchModeToggle
        if let error = phone.lastError {
          Text(error).font(.caption2).foregroundStyle(.red).multilineTextAlignment(.center)
        }
      }
      .padding(.horizontal, 4)
    }
  }

  /// "PAUSED · FEET CUT OFF" when paused, "waiting for the picture" before the first preview arrives.
  private var hintText: String {
    guard phone.preview != nil else { return "waiting for the picture" }
    let hint = status.frame.hint.uppercased()
    return status.paused ? "PAUSED · \(hint)" : hint
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

  /// Rest since Done, counting up; orange past the rest length (story 046). The 2 s clock above refreshes it.
  @ViewBuilder private var restStatus: some View {
    if let restEnded = phone.rest.restEnded {
      (Text("Rest ") + Text(restEnded, style: .timer))
        .font(.headline).monospacedDigit()
        .foregroundStyle(
          Date().timeIntervalSince(restEnded) >= Double(phone.rest.length) ? .orange : .primary)
    }
  }

  /// Rest length between sets, a watch setting (story 046).
  private var restPicker: some View {
    Picker("Rest", selection: Binding(get: { phone.rest.length }, set: { phone.rest.length = $0 })) {
      ForEach(RestTimer.choices, id: \.self) { seconds in
        Text(String(format: "%d:%02d", seconds / 60, seconds % 60)).tag(seconds)
      }
    }
    .pickerStyle(.navigationLink)
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

  private static func duration(_ seconds: Double) -> String {
    let total = Int(seconds)
    return String(format: "%d:%02d", total / 60, total % 60)
  }
}
