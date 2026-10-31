// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import Combine
import ExerciseCore
import SwiftUI
import WatchKit

struct WatchContentView: View {
  let phone: PhoneLink
  @Environment(\.scenePhase) private var scenePhase
  /// Ticks so a status that stops arriving turns stale on screen.
  @State private var now = Date()
  @State private var confirmDiscard = false
  /// Start under ten minutes after an End asks to continue that workout (#238); the question, set at the tap.
  @State private var askingContinue = false
  @State private var continueQuestion = ""
  /// The count page of a set typed by hand is up (059).
  @State private var countingSet = false
  private let clock = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

  private var status: WatchStatus { phone.status }
  private var workout: WorkoutController { phone.workout }

  var body: some View {
    Group {
      // The picture page whenever the camera is live: `recording` means the camera is up. `phoneActive` is the
      // follow-the-wrist decision (041), never a gate on the picture (2026-09-13 regression: the wrist dropped to
      // the idle pages whenever the phone app was not .active, and lost its framing controls with it).
      if (phone.showsAsLive || phone.answersLost) && status.recording {
        recordingPages
      } else {
        idlePages
      }
    }
    .onReceive(clock) {
      now = $0
      if !phone.isLive { phone.ping() }
    }
    // Also pings: the phone learns the app is in front even without a scene change.
    .onAppear { phone.sceneActive(true) }
    .onChange(of: scenePhase) { _, phase in phone.sceneActive(phase == .active) }
    // Redraw when the wake grace runs out, so a phone that never answered is shown as such on time.
    .task(id: scenePhase) {
      guard scenePhase == .active else { return }
      try? await Task.sleep(for: .seconds(PhoneLink.wakeGrace + 0.1))
      now = Date()
    }
  }

  /// Everything that is not a recording: the not-connected, backgrounded-phone and idle screens. A running
  /// workout (048) heads every one of them with its clock and heart rate and ends them with End and Discard:
  /// the workout is the wrist's, whatever the phone is doing.
  private var idlePages: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(spacing: 8) {
          if workout.running { workoutHeader }
          if phone.noVideos {
            // Workout only, no videos (071, #236): nothing about the phone, no Record, no Preview; the workout,
            // the sets typed by hand and the rest are the wrist's own; the count page picks the exercise (#154).
            if !workout.running {
              Image(systemName: "video.slash").font(.largeTitle).foregroundStyle(.secondary)
            }
            Text("No videos for a while: workout only").font(.caption).multilineTextAlignment(.center)
              .foregroundStyle(.secondary)
            if let hand = phone.handSet, hand.isNewer(than: status.lastSet) {
              Text("Last set").font(.caption2).foregroundStyle(.secondary)
              Text("\(hand.reps) reps · \(hand.exercise.definition.name) · by hand")
                .font(.headline).monospacedDigit()
            }
            startWorkoutButton
            setByHandButton
            if !workout.running { restStatus }
            restPicker
            noVideosToggle
          } else if !phone.showsAsLive {
            if !workout.running {
              Image(systemName: "iphone.slash").font(.largeTitle).foregroundStyle(.secondary)
            }
            Text(
              phone.reachable
                ? "Waiting for the phone…"
                : "Not connected to the phone. It reconnects on its own; if it doesn't, open Exercise Analyzer on the phone."
            )
            .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
            if status.rolling {
              Text("Last seen recording: \(status.reps) reps").font(.caption2).foregroundStyle(.tertiary)
            }
            if let since = phone.receivedAt {
              // Reconnects by itself (retries every 2 s); this just says how long it has been.
              Text("Last heard \(Int(max(0, now.timeIntervalSince(since)))) s ago").font(.caption2).foregroundStyle(
                .tertiary)
            }
            startWorkoutButton
            Button {
              phone.retry()
            } label: {
              Label(phone.retrying ? "Trying…" : "Retry", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }
            setByHandButton  // the set waits for the phone (059)
            noVideosToggle
          } else if !status.phoneActive {
            if !workout.running {
              Image(systemName: "iphone.gen3").font(.largeTitle).foregroundStyle(.secondary)
            }
            Text(
              "The phone app is in the background. Unlock the phone and open Exercise Analyzer; it stays awake while the watch is connected."
            )
            .font(.caption2).multilineTextAlignment(.center).foregroundStyle(.secondary)
            startWorkoutButton
            Button {
              phone.send(.start)
            } label: {
              Label("Send a reminder to the phone", systemImage: "bell").frame(maxWidth: .infinity)
            }
            setByHandButton
            noVideosToggle
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
            } else if let hand = phone.handSet, hand.isNewer(than: status.lastSet) {
              // A set typed here after the phone's last one (059).
              Text("Last set").font(.caption2).foregroundStyle(.secondary)
              Text("\(hand.reps) reps · \(hand.exercise.definition.name) · by hand")
                .font(.headline).monospacedDigit()
            } else if let last = status.lastSet {
              Text("Last set").font(.caption2).foregroundStyle(.secondary)
              Text("\(last.reps) reps · \(last.exercise) · \(Self.duration(last.seconds))")
                .font(.headline).monospacedDigit()
            }
            startWorkoutButton
            Button {
              phone.send(.start)
            } label: {
              Label("Record", systemImage: "record.circle").frame(maxWidth: .infinity)
            }
            .tint(.red)
            .disabled(!phone.reachable)
            // Framing first: the camera without the recorder, then Record from the picture (047, #73).
            Button {
              phone.send(.viewfinder)
            } label: {
              Label("Preview", systemImage: "camera.fill").frame(maxWidth: .infinity)
            }
            .disabled(!phone.reachable)
            // Under Preview, above the pickers (Igor's pick, 2026-09-26): Record and Preview stay where the hand goes.
            setByHandButton
            if !workout.running { restStatus }  // inside a workout the head carries the rest (050)
            restPicker
            exercisePicker
            noVideosToggle
          }
          if workout.running { workoutEndButtons.id("workout-end") }
          if let error = phone.noVideos ? workout.lastError : phone.lastError ?? workout.lastError {
            Text(error).font(.caption2).foregroundStyle(.red).multilineTextAlignment(.center)
          }
        }
        .padding(.horizontal, 4)
      }
      .onAppear {
        // The screenshot rung's setByHand state: the workout page with the count page over it.
        if phone.screenshotOpensSetByHand { countingSet = true }
        // The screenshot rung's workoutEnd state: the same page, scrolled to its bottom.
        guard phone.screenshotScrollsToEnd else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo("workout-end", anchor: .bottom) }
      }
      .sheet(isPresented: $countingSet) {
        let start = HandSet.start(mode: status.mode, analyzed: status.lastSet, byHand: phone.lastTyped)
        NavigationStack {
          SetByHandPage(
            exercise: start.exercise, start: start.reps, choosing: phone.screenshotOpensExerciseList,
            startKg: {
              HandSet.startKg(for: $0, phone: status.bellKg, typed: phone.lastTyped, analyzed: status.lastSet)
            },
            log: { phone.logEvent($0, $1) }
          ) { exercise, reps, kg in
            phone.saveSetByHand(exercise: exercise, reps: reps, kg: kg)
          }
        }
      }
    }
  }

  /// No videos for a while (071, #236; Igor: "not going to record videos for a while"): under the pickers on
  /// every idle page; orange while on, when it reads "Videos again".
  private var noVideosToggle: some View {
    Button {
      phone.setNoVideos(!phone.noVideos)
    } label: {
      Label(
        phone.noVideos ? "Videos again" : "No videos for a while", systemImage: phone.noVideos ? "video" : "video.slash"
      )
      .frame(maxWidth: .infinity)
    }
    .tint(phone.noVideos ? .orange : nil)
  }

  /// A set done without Record (059): only inside a workout, which it belongs to; the count page does the rest.
  @ViewBuilder private var setByHandButton: some View {
    if workout.running {
      Button {
        countingSet = true
      } label: {
        Label("Set by hand", systemImage: "plus").frame(maxWidth: .infinity)
      }
      .disabled(workout.phase == .ending)
    }
  }

  /// The workout page's head (048): the session clock ticking by itself, the heart rate, the sets so far.
  /// Between sets the head flips (050): the rest is the number acted on, so it is the large one, white until the
  /// rest length and orange after, and the session clock goes small and green beside the heart rate.
  private var workoutHeader: some View {
    let resting = workout.phase == .ending ? nil : phone.rest.restEnded
    let drop = resting == nil ? nil : workout.setPeak.drop(now: workout.heartRate)
    // A continued workout (#238) shows from its first part: that clock, those sets with this session's.
    let tally = workout.shownTally
    return VStack(spacing: 2) {
      if let resting {
        Text("REST · \(Self.duration(Double(phone.rest.length)))")
          .font(.caption2.weight(.semibold)).kerning(1).foregroundStyle(.orange)
        Text(resting, style: .timer)
          .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
          .foregroundStyle(restIsOver(resting) ? .orange : .primary)
      } else {
        Text(workout.phase == .ending ? "ENDING…" : "WORKOUT")
          .font(.caption2.weight(.semibold)).kerning(1).foregroundStyle(.green)
        if let startedAt = workout.shownStart {
          Text(startedAt, style: .timer)
            .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
        }
      }
      HStack(spacing: 4) {
        Image(systemName: "heart.fill").font(.caption).foregroundStyle(.red)
        heartLine(drop: drop, clock: resting == nil ? nil : workout.shownStart)
          // One text, so it shrinks as a whole: as separate texts the drop wrapped on the 49 mm face and
          // truncated with the clock on the 40 mm (#195).
          .lineLimit(1)
          .minimumScaleFactor(0.5)
      }
      .accessibilityLabel(
        "Heart rate \(workout.heartRate.map(String.init) ?? "unknown")"
          + (drop.map { ", \($0) below the last set's peak" } ?? ""))
      // The sets by exercise with the drawings, as the phone's Today line reads mid-workout (#206, #192; Igor:
      // "show sets and exercises completed like I see it on the workouts view … just those coarse details"),
      // and nothing else: "6 sets · 47 reps" went ("drop n sets reps, the icons are enough").
      if !tally.exerciseOrder.isEmpty {
        HStack(spacing: 8) {
          ForEach(tally.exerciseOrder) { kind in
            HStack(spacing: 2) {
              ExerciseGlyph(kind: kind, size: 16)
              Text("\(tally.exerciseSets[kind, default: 0])").font(.caption.bold()).monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(tally.exerciseSets[kind, default: 0]) sets of \(kind.repWord(2))")
          }
        }
        .padding(.top, 2)
      } else if tally.sets > 0 {
        // Sets with no exercise to draw (a name the watch does not know, a tally saved before #206) still show.
        Text("\(tally.sets) set\(tally.sets == 1 ? "" : "s") · \(tally.reps) reps")
          .font(.caption).monospacedDigit().foregroundStyle(.secondary)
      }
    }
    .padding(.bottom, 4)
  }

  /// "128 BPM", resting "128 · −29 BPM · 42:13": the rate now, its drop from the last recorded set's peak
  /// (#195) and the session clock small and green (050).
  private func heartLine(drop: Int?, clock: Date?) -> Text {
    let rate = Text(workout.heartRate.map(String.init) ?? "--").font(.title3.bold()).monospacedDigit()
    let fall = drop.map { Text(" · −\($0)").font(.title3.bold()).monospacedDigit() } ?? Text("")
    let unit = Text(" BPM").font(.caption2).foregroundStyle(.secondary)
    let session =
      clock.map {
        Text(" · ").foregroundStyle(.secondary)
          + Text($0, style: .timer).font(.title3.bold()).monospacedDigit().foregroundStyle(.green)
      } ?? Text("")
    return rate + fall + unit + session
  }

  /// Start by hand, above Record (048): the warm-up is workout time. Gone once the workout runs.
  @ViewBuilder private var startWorkoutButton: some View {
    if !workout.running {
      Button {
        // Igor (#238): "On quick restart workout ask if want to continue."
        if let ended = workout.continuable {
          continueQuestion = ended.question(at: Date())
          askingContinue = true
        } else {
          phone.startWorkout()
        }
      } label: {
        Label(workout.phase == .starting ? "Starting…" : "Start workout", systemImage: "clock")
          .frame(maxWidth: .infinity)
      }
      .tint(.green)
      .disabled(workout.phase == .starting)
      .confirmationDialog(continueQuestion, isPresented: $askingContinue, titleVisibility: .visible) {
        Button("Continue") { phone.startWorkout(continuing: true) }
        Button("New workout") { phone.startWorkout() }
      }
    }
  }

  /// At the bottom of the page, under the pickers: End writes the workout to Health, Discard asks first.
  private var workoutEndButtons: some View {
    VStack(spacing: 8) {
      Button {
        phone.endWorkout(discard: false)
      } label: {
        Label("End workout", systemImage: "checkmark").frame(maxWidth: .infinity)
      }
      .tint(.green)
      Button(role: .destructive) {
        confirmDiscard = true
      } label: {
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
        // Framing, not recording: no count, no time (047); the rest keeps counting beside the chip (050).
        HStack(spacing: 6) {
          Spacer(minLength: 0)
          Text("PREVIEW")
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(.ultraThinMaterial, in: Capsule())
          if let restEnded = phone.rest.restEnded {
            (Text("REST ") + Text(restEnded, style: .timer))
              .font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
              .foregroundStyle(restIsOver(restEnded) ? .orange : .primary)
              .lineLimit(1).fixedSize()
              .padding(.horizontal, 8).padding(.vertical, 2)
              .background(.ultraThinMaterial, in: Capsule())
          }
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        // The workout's heart rate while framing (#106): the rest and the heart are what say "go again". A
        // line of its own, because PREVIEW, the rest and the heart do not fit one row even on the Ultra.
        heartRateChip
      } else {
        HStack {
          Text("\(status.reps)")
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .padding(.horizontal, 8).padding(.vertical, 1)
            .background(.ultraThinMaterial, in: Capsule())
          Spacer()
          heartRateChip
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
        .background(
          phone.answersLost
            ? Color.orange.opacity(0.8) : status.frame.inFrame ? Color.green.opacity(0.4) : Color.red.opacity(0.7),
          in: Capsule()
        )
        .padding(.bottom, 2)
    }
    .safeAreaInset(edge: .bottom) {
      HStack(spacing: 8) {
        if status.viewfinder {
          // Record · Camera · Cancel: no Pause, no Done (047).
          Button {
            phone.send(.start)
          } label: {
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
          Button {
            phone.send(status.paused ? .resume : .pause)
          } label: {
            Image(systemName: status.paused ? "play.fill" : "pause.fill")
              .font(.body)
              .frame(width: 40, height: 40)
              .background(
                status.paused ? AnyShapeStyle(Color.orange.opacity(0.8)) : AnyShapeStyle(.ultraThinMaterial),
                in: Circle()
              )
              .foregroundStyle(.white)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(status.paused ? "Resume" : "Pause")
          faceCameraButton
          Button {
            phone.send(.finish)
          } label: {
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

  /// The workout's heart rate on the picture page, recording (048) or framing (#106); no workout, no chip.
  @ViewBuilder private var heartRateChip: some View {
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
  }

  /// The round camera-cycler both face rows share.
  private var faceCameraButton: some View {
    Button {
      phone.send(.switchCamera)
    } label: {
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
    Button {
      phone.send(.cancel)
    } label: {
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
        Button(role: .destructive) {
          phone.send(.cancel)
        } label: {
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
    if phone.answersLost { return "PHONE NOT ANSWERING · TAPS STILL REACH IT" }
    guard phone.preview != nil else { return "waiting for the picture" }
    let hint = status.frame.hint.uppercased()
    return status.paused ? "PAUSED · \(hint)" : hint
  }

  /// Watch mode on the phone: big digits on its screen, everything driven from here. Only while recording: the
  /// phone refuses it otherwise (#36).
  private var watchModeToggle: some View {
    Button {
      phone.send(.watchMode)
    } label: {
      Label(
        status.watchMode ? "Phone: watch mode on" : "Phone: watch mode",
        systemImage: status.watchMode ? "iphone.gen3.radiowaves.left.and.right" : "iphone.gen3"
      )
      .frame(maxWidth: .infinity)
    }
    .tint(status.watchMode ? .blue : nil)
  }

  /// Rest since Done, counting up; orange past the rest length (story 046). The 2 s clock above refreshes it.
  @ViewBuilder private var restStatus: some View {
    if let restEnded = phone.rest.restEnded {
      (Text("Rest ") + Text(restEnded, style: .timer))
        .font(.headline).monospacedDigit()
        .foregroundStyle(restIsOver(restEnded) ? .orange : .primary)
    }
  }

  /// Past the rest length; read off the 2 s clock so the colour turns without a status arriving.
  private func restIsOver(_ restEnded: Date) -> Bool {
    now.timeIntervalSince(restEnded) >= Double(phone.rest.length)
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
    let options: [(String, String)] =
      [("auto", "Auto")] + ExerciseKind.analyzable.map { ($0.rawValue, $0.definition.name) }
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

/// The count of a set typed by hand (059): the exercise on top, the reps, − and + (44 pt) and the Crown step them by
/// one with a tick each, 1…200, then the weight. The exercise row opens the drawings, and the one tapped there is the
/// set's (#154). The green checkmark at top right saves the set; the sheet's close button adds nothing.
private struct SetByHandPage: View {
  /// Exercise, reps and the bell's weight (nil for none).
  let onSave: (ExerciseKind, Int, Int?) -> Void
  /// Each exercise's last weight (#271): the weight row opens on it and follows the exercise until turned.
  let startKg: (ExerciseKind) -> Int?
  let log: (String, [String: Any]) -> Void
  /// Taps on the weight row so far, for `kg_row_tap`: whether the first one opened the tiles (ea-bgi).
  @State private var kgTaps = 0
  @State private var exercise: ExerciseKind
  /// The Crown's value; the count is it rounded and clamped.
  @State private var count: Double
  @State private var choosing = false
  /// The weight row's Crown value: 0 for none, then `HandSet.weights` in order.
  @State private var kgStep: Double
  @State private var kgPicked = false
  @State private var pickingKg = false
  @FocusState private var crownFocused: Bool
  @FocusState private var kgFocused: Bool
  @Environment(\.dismiss) private var dismiss

  init(
    exercise: ExerciseKind, start: Int, choosing: Bool = false, startKg: @escaping (ExerciseKind) -> Int?,
    log: @escaping (String, [String: Any]) -> Void, onSave: @escaping (ExerciseKind, Int, Int?) -> Void
  ) {
    self.onSave = onSave
    self.startKg = startKg
    self.log = log
    _exercise = State(initialValue: exercise)
    _count = State(initialValue: Double(start))
    _choosing = State(initialValue: choosing)
    _kgStep = State(initialValue: Self.step(for: startKg(exercise)))
  }

  private var reps: Int { HandSet.clamp(Int(count.rounded())) }

  private var kg: Int? {
    let step = Int(kgStep.rounded())
    return HandSet.weights.indices.contains(step - 1) ? HandSet.weights[step - 1] : nil
  }

  /// A weight off the code (a 34 kg tapped on the phone) opens on the nearest bell.
  private static func step(for kg: Int?) -> Double {
    guard let kg else { return 0 }
    let nearest = HandSet.weights.indices.min { abs(HandSet.weights[$0] - kg) < abs(HandSet.weights[$1] - kg) }
    return Double((nearest ?? -1) + 1)
  }

  /// Three full-width rows (ea-xrf, Igor picked A on the 2026-10-17 Lavish page: "the tap targets really are hard
  /// to use for setting weights"): the exercise, the reps, the weight. The green row is the Crown's; a tap on a row
  /// gives it the Crown, and a second tap on the weight row, or any tap on the exercise row, opens big tiles.
  /// The checkmark at top right saves and the sheet's close button cancels, so the rows fit a 40 mm face unscrolled.
  var body: some View {
    ScrollView {
      VStack(spacing: 5) {
        Button {
          choosing = true
        } label: {
          row(green: false) {
            ExerciseGlyph(kind: exercise, size: 28)
            Text(exercise.definition.name).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Exercise: \(exercise.definition.name). Change")
        row(green: crownFocused) {
          stepButton("minus", by: -1)
          VStack(spacing: 0) {
            Text("\(reps)").font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
            Text("reps").font(.caption2).foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
          stepButton("plus", by: 1)
        }
        .focusable()
        .focused($crownFocused)
        .digitalCrownRotation(
          $count, from: Double(HandSet.range.lowerBound), through: Double(HandSet.range.upperBound), by: 1,
          sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true
        )
        .onTapGesture { crownFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(reps) reps")
        // The bell's weight (#271): a tap gives it the Crown, which steps None, 8 … 36 kg; a tap on the green row
        // opens every bell as a tile.
        row(green: kgFocused) {
          Text("kg").font(.caption).foregroundStyle(.secondary)
          Text(kg.map { "\($0)" } ?? "None")
            .font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
            .foregroundStyle(kg == nil ? .secondary : .primary)
          Spacer(minLength: 0)
          Image(systemName: kgFocused ? "square.grid.2x2" : "chevron.right").font(.caption.bold())
            .foregroundStyle(.secondary)
        }
        .focusable()
        .focused($kgFocused)
        .digitalCrownRotation(
          $kgStep, from: 0, through: Double(HandSet.weights.count), by: 1, sensitivity: .low, isContinuous: false,
          isHapticFeedbackEnabled: true
        )
        .onTapGesture {
          kgTaps += 1
          // Instrumented (ea-bgi): whether watchOS had already focused the row when the tap's closure ran.
          log("kg_row_tap", ["tap": kgTaps, "focused": kgFocused])
          if kgFocused { pickingKg = true } else { kgFocused = true }
        }
        // Given the Crown, the weight is the lifter's: a change of exercise no longer moves it.
        .onChange(of: kgFocused) { _, focused in if focused { kgPicked = true } }
        .accessibilityLabel(kg.map { "\($0) kilograms. Turn the Crown to change" } ?? "No weight")
        .accessibilityAddTraits(.isButton)
      }
    }
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button {
          onSave(exercise, reps, kg)
          dismiss()
        } label: {
          Image(systemName: "checkmark")
        }
        .tint(.green)
        .accessibilityLabel("Save")
      }
    }
    .onAppear { crownFocused = true }
    .sheet(isPresented: $choosing, onDismiss: { crownFocused = true }, content: { exercisePicker })
    .sheet(isPresented: $pickingKg, onDismiss: { kgFocused = true }, content: { kgPicker })
  }

  /// A row of the page: full width, at least 44 pt, outlined green while it has the Crown.
  private func row<Content: View>(green: Bool, @ViewBuilder _ content: () -> Content) -> some View {
    HStack(spacing: 6) { content() }
      .padding(.horizontal, 8)
      .frame(maxWidth: .infinity, minHeight: 44)
      .background(
        green ? Color.green.opacity(0.18) : Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14)
      )
      .overlay(RoundedRectangle(cornerRadius: 14).stroke(green ? Color.green : .clear, lineWidth: 2))
      .contentShape(RoundedRectangle(cornerRadius: 14))
  }

  /// The exercises as their drawings, three across, 52 pt each (ea-xrf): one tap picks.
  private var exercisePicker: some View {
    ScrollView {
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
        ForEach(ExerciseKind.allCases) { kind in
          Button {
            exercise = kind
            // An exercise with a usual count opens on it (#196); the others keep the count on the page.
            if let usual = HandSet.usualReps(for: kind) { count = Double(usual) }
            // And its last weight, unless one was turned to (#271).
            if !kgPicked { kgStep = Self.step(for: startKg(kind)) }
            choosing = false
          } label: {
            ExerciseGlyph(kind: kind, size: 36)
              .frame(maxWidth: .infinity, minHeight: 52)
              .background(
                kind == exercise ? kind.tint.opacity(0.3) : Color.secondary.opacity(0.18),
                in: RoundedRectangle(cornerRadius: 12)
              )
              .overlay(RoundedRectangle(cornerRadius: 12).stroke(kind == exercise ? Color.white : .clear, lineWidth: 2))
          }
          .buttonStyle(.plain)
          .accessibilityLabel(kind.definition.name)
          .accessibilityAddTraits(kind == exercise ? .isSelected : [])
        }
      }
    }
  }

  /// Every bell as a tile, None first, four across (ea-xrf): one tap picks and closes. It scrolls: with 36 kg
  /// (#334) the three rows pass the 40 mm's sheet.
  private var kgPicker: some View {
    ScrollView {
      kgTiles
    }
  }

  private var kgTiles: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 4), spacing: 5) {
      ForEach(0...HandSet.weights.count, id: \.self) { step in
        let picked = Int(kgStep.rounded()) == step
        Button {
          kgStep = Double(step)
          kgPicked = true
          pickingKg = false
        } label: {
          Text(step == 0 ? "—" : "\(HandSet.weights[step - 1])")
            .font(.headline).monospacedDigit()
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(picked ? Color.black : .primary)
            .background(picked ? Color.green : Color.secondary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(step == 0 ? "No weight" : "\(HandSet.weights[step - 1]) kilograms")
        .accessibilityAddTraits(picked ? .isSelected : [])
      }
    }
  }

  private func stepButton(_ symbol: String, by step: Int) -> some View {
    Button {
      count = Double(HandSet.clamp(reps + step))
      crownFocused = true
      WKInterfaceDevice.current().play(.click)
    } label: {
      Image(systemName: symbol)
        .font(.title3.bold())
        .frame(width: 44, height: 44)
        .background(Color.secondary.opacity(0.3), in: Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(step < 0 ? "One rep fewer" : "One rep more")
  }
}
