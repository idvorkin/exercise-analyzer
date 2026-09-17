// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import ExerciseCore
import SwiftUI

struct WatchContentView: View {
  @ObservedObject var phone: PhoneLink
  @Environment(\.scenePhase) private var scenePhase
  /// Ticks so a status that stops arriving turns stale on screen.
  @State private var now = Date()
  @State private var confirmDiscard = false
  private let clock = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

  private var status: WatchStatus { phone.status }
  private var workout: WorkoutController { phone.workout }

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

  /// Everything that is not a recording: the not-connected, backgrounded-phone and idle screens. A running
  /// workout (048) heads every one of them with its clock and heart rate and ends them with End and Discard:
  /// the workout is the wrist's, whatever the phone is doing.
  private var idlePages: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(spacing: 8) {
          if workout.running { workoutHeader }
          if !phone.isLive {
            if !workout.running {
              Image(systemName: "iphone.slash").font(.largeTitle).foregroundStyle(.secondary)
            }
            Text(phone.reachable ? "Waiting for the phone…" : "Not connected to the phone. It reconnects on its own; if it doesn't, open Exercise Analyzer on the phone.")
              .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
            if status.rolling {
              Text("Last seen recording: \(status.reps) reps").font(.caption2).foregroundStyle(.tertiary)
            }
            if let since = phone.receivedAt {
              // Reconnects by itself (retries every 2 s); this just says how long it has been.
              Text("Last heard \(Int(max(0, now.timeIntervalSince(since)))) s ago").font(.caption2).foregroundStyle(.tertiary)
            }
            startWorkoutButton
            Button { phone.ping() } label: { Label("Retry", systemImage: "arrow.clockwise").frame(maxWidth: .infinity) }
          } else if !status.phoneActive {
            if !workout.running {
              Image(systemName: "iphone.gen3").font(.largeTitle).foregroundStyle(.secondary)
            }
            Text("The phone app is in the background. Unlock the phone and open Exercise Analyzer; it stays awake while the watch is connected.")
              .font(.caption2).multilineTextAlignment(.center).foregroundStyle(.secondary)
            startWorkoutButton
            Button { phone.send(.start) } label: {
              Label("Send a reminder to the phone", systemImage: "bell").frame(maxWidth: .infinity)
            }
          } else {
            if !workout.running {
              Image(systemName: "figure.strengthtraining.traditional").font(.largeTitle).foregroundStyle(.secondary)
              Text(phone.reachable ? "Phone ready" : "Open Exercise Analyzer on the phone")
                .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            // The offline pass's final count (045): "Analyzing…" while it runs, then the last set's line. The
            // next recording status carries neither and the line goes.
            if status.phase == "analyzing" {
              Text("Analyzing…").font(.caption).foregroundStyle(.secondary)
            } else if let last = status.lastSet {
              Text("Last set").font(.caption2).foregroundStyle(.secondary)
              Text("\(last.reps) reps · \(last.exercise) · \(Self.duration(last.seconds))")
                .font(.headline).monospacedDigit()
            }
            startWorkoutButton
            Button { phone.send(.start) } label: {
              Label("Record", systemImage: "record.circle").frame(maxWidth: .infinity)
            }
            .tint(.red)
            .disabled(!phone.reachable)
            // Framing first: the camera without the recorder, then Record from the picture (047, #73).
            Button { phone.send(.viewfinder) } label: {
              Label("Preview", systemImage: "camera.fill").frame(maxWidth: .infinity)
            }
            .disabled(!phone.reachable)
            restStatus
            restPicker
            exercisePicker
          }
          if workout.running { workoutEndButtons.id("workout-end") }
          if let error = phone.lastError ?? workout.lastError {
            Text(error).font(.caption2).foregroundStyle(.red).multilineTextAlignment(.center)
          }
        }
        .padding(.horizontal, 4)
      }
      .onAppear {
        // The screenshot rung's workoutEnd state: the same page, scrolled to its bottom.
        guard phone.screenshotScrollsToEnd else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo("workout-end", anchor: .bottom) }
      }
    }
  }

  /// The workout page's head (048): the session clock ticking by itself, the heart rate, the sets so far.
  private var workoutHeader: some View {
    VStack(spacing: 2) {
      Text(workout.phase == .ending ? "ENDING…" : "WORKOUT")
        .font(.caption2.weight(.semibold)).kerning(1).foregroundStyle(.green)
      if let startedAt = workout.startedAt {
        Text(startedAt, style: .timer)
          .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
      }
      HStack(spacing: 4) {
        Image(systemName: "heart.fill").font(.caption).foregroundStyle(.red)
        Text(workout.heartRate.map(String.init) ?? "--")
          .font(.title3.bold()).monospacedDigit()
        Text("BPM").font(.caption2).foregroundStyle(.secondary)
      }
      .accessibilityLabel("Heart rate \(workout.heartRate.map(String.init) ?? "unknown")")
      Text("\(workout.sets) set\(workout.sets == 1 ? "" : "s") · \(workout.reps) reps")
        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
    }
    .padding(.bottom, 4)
  }

  /// Start by hand, above Record (048): the warm-up is workout time. Gone once the workout runs.
  @ViewBuilder private var startWorkoutButton: some View {
    if !workout.running {
      Button { phone.startWorkout() } label: {
        Label(workout.phase == .starting ? "Starting…" : "Start workout", systemImage: "clock")
          .frame(maxWidth: .infinity)
      }
      .tint(.green)
      .disabled(workout.phase == .starting)
    }
  }

  /// At the bottom of the page, under the pickers: End writes the workout to Health, Discard asks first.
  private var workoutEndButtons: some View {
    VStack(spacing: 8) {
      Button { phone.endWorkout(discard: false) } label: {
        Label("End workout", systemImage: "checkmark").frame(maxWidth: .infinity)
      }
      .tint(.green)
      Button(role: .destructive) { confirmDiscard = true } label: {
        Label("Discard", systemImage: "trash").frame(maxWidth: .infinity)
      }
      .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
        Button("Discard", role: .destructive) { phone.endWorkout(discard: true) }
      } message: {
        Text("Nothing goes to Health. The sets you recorded stay in Workouts.")
      }
      Text("End writes one workout to Health").font(.caption2).foregroundStyle(.tertiary)
    }
    .disabled(workout.phase == .ending)
    .padding(.top, 8)
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

  /// Page one: the preview filling the screen, small chips right under the clock line, a compact hint capsule
  /// and the round buttons along the bottom edge of the safe area. No picture yet: the same overlays on black.
  /// Only the picture ignores the safe area. The overlays cover as little of the picture as 40 pt targets allow
  /// (Igor, 2026-09-14: "avoid covering the screen, buttons at the bottom, more transparency"): the row is
  /// inset 10 pt from both sides with 40 pt buttons 8 pt apart (200 pt on the Ultra's 205 pt face), inside the
  /// bottom safe area and lifted 18 pt, so the rounded corners keep nothing (refs #74). A row wider than the face
  /// widens the whole overlay.
  /// The picture is a `background`, never a ZStack sibling: a scaled-to-fill image reports its overflowing size
  /// and a ZStack grows to it, which pushed the chips and the row past the screen edges on the Ultra.
  private var recordingPicturePage: some View {
    recordingOverlays
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background {
        Color.clear
          .overlay {
            if let preview = phone.preview {
              Image(uiImage: preview).resizable().scaledToFill()
            } else {
              Color.black
            }
          }
          .clipped()
          .ignoresSafeArea()
      }
  }

  private var recordingOverlays: some View {
      VStack(spacing: 6) {
        if status.viewfinder {
          // Framing, not recording: one chip, no count, no time (047).
          HStack {
            Spacer()
            Text("PREVIEW")
              .font(.system(size: 15, weight: .semibold, design: .rounded))
              .padding(.horizontal, 8).padding(.vertical, 2)
              .background(.ultraThinMaterial, in: Capsule())
            Spacer()
          }
          .padding(.horizontal, 8)
          .padding(.top, 2)
        } else {
          HStack {
            Text("\(status.reps)")
              .font(.system(size: 24, weight: .bold, design: .rounded))
              .padding(.horizontal, 8).padding(.vertical, 1)
              .background(.ultraThinMaterial, in: Capsule())
            Spacer()
            // The workout's heart rate rides along on the picture page (048); no workout, no chip.
            if workout.running, let heartRate = workout.heartRate {
              HStack(spacing: 3) {
                Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(.red)
                Text("\(heartRate)").monospacedDigit()
              }
              .font(.system(size: 16, weight: .semibold, design: .rounded))
              .padding(.horizontal, 8).padding(.vertical, 3)
              .background(.ultraThinMaterial, in: Capsule())
              .accessibilityLabel("Heart rate \(heartRate)")
            }
            Text(elapsed).monospacedDigit()
              .font(.system(size: 16, weight: .semibold, design: .rounded))
              .padding(.horizontal, 8).padding(.vertical, 3)
              .background(.ultraThinMaterial, in: Capsule())
          }
          .padding(.horizontal, 8)
          .padding(.top, 2)
        }
        Spacer()
        // A capsule as wide as its words, not a bar across the picture; red stays strong enough to read.
        Text(hintText)
          .font(.caption2.weight(.semibold)).multilineTextAlignment(.center)
          .padding(.horizontal, 10).padding(.vertical, 3)
          .background(status.frame.inFrame ? Color.green.opacity(0.4) : Color.red.opacity(0.7), in: Capsule())
          .padding(.bottom, 2)
      }
      .safeAreaInset(edge: .bottom) {
        HStack(spacing: 8) {
          if status.viewfinder {
            // Record · Camera · Cancel: no Pause, no Done (047).
            Button { phone.send(.start) } label: {
              Image(systemName: "record.circle")
                .font(.body)
                .frame(width: 40, height: 40)
                .background(Color.red.opacity(0.8), in: Circle())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Record")
            faceCameraButton
            faceCancelButton
          } else {
            Button { phone.send(status.paused ? .resume : .pause) } label: {
              Image(systemName: status.paused ? "play.fill" : "pause.fill")
                .font(.body)
                .frame(width: 40, height: 40)
                .background(status.paused ? AnyShapeStyle(Color.orange.opacity(0.8)) : AnyShapeStyle(.ultraThinMaterial), in: Circle())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(status.paused ? "Resume" : "Pause")
            faceCameraButton
            Button { phone.send(.finish) } label: {
              Image(systemName: "checkmark")
                .font(.body.bold())
                .frame(width: 40, height: 40)
                .background(Color.green.opacity(0.75), in: Circle())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done")
            faceCancelButton
          }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 18)
      }
      // The row lives in the bottom safe area (the Ultra reserves ~34 pt there): lifted 18 pt and inset 10 pt,
      // the outer buttons' lower corners stay outside a 60 pt corner radius. The phone rung is the truth for
      // the real bezel; the simulator raster has no corner mask.
      .ignoresSafeArea(edges: .bottom)
  }

  /// The round camera-cycler both face rows share.
  private var faceCameraButton: some View {
    Button { phone.send(.switchCamera) } label: {
      Text(cameraLevel)
        .font(.caption.bold())
        .minimumScaleFactor(0.5).lineLimit(1)
        .frame(width: 40, height: 40)
        .background(.ultraThinMaterial, in: Circle())
        .foregroundStyle(.white)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Camera: \(cameraLevel)")
  }

  /// The round cancel both face rows share.
  private var faceCancelButton: some View {
    Button { phone.send(.cancel) } label: {
      Image(systemName: "xmark")
        .font(.body.bold())
        .frame(width: 36, height: 36)
        .background(.ultraThinMaterial, in: Circle())
        .foregroundStyle(.red)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Cancel")
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
