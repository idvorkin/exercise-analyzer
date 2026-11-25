// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The cardio machine's setting on the workout page (story 085, ea-jap; Larry, 2026-11-24: "a 'level' event type
//  the moment he changes incline or intensity … so heart rate can be read per level"): the machine's name, its
//  incline and its intensity as three full-width rows. A tap gives a number row the Crown, − and + step it, and
//  two seconds after the last step the setting goes to the phone, which sends Larry one `level`.

import ExerciseCore
import SwiftUI
import WatchKit

struct MachineRows: View {
  typealias Machine = WorkoutEvent.Machine

  let workout: WorkoutController
  /// The screenshot rung's workoutMachine state: Incline holds the Crown.
  var focusOnAppear: Machine.Setting?
  /// What the rows show, ahead of the commit; the controller's own once a commit is through.
  @State private var draft: Machine?
  @State private var draftAt: Date?
  @State private var inclineCrown = 0.0
  @State private var intensityCrown = 0.0
  @State private var picking = false
  @State private var commit: Task<Void, Never>?
  @FocusState private var focused: Machine.Setting?

  /// Taken after the Crown rests this long: one `level` for a sweep, not one per detent.
  static let settle: Duration = .seconds(2)

  private var shown: Machine? { draft ?? workout.machine }

  var body: some View {
    if let machine = shown {
      // The numbers first, right under the head where the hand goes; the machine, changed less, under them.
      VStack(spacing: 5) {
        numberRow(.incline, title: "Incline", value: machine.incline, crown: $inclineCrown)
        numberRow(.intensity, title: "Intensity", value: machine.intensity, crown: $intensityCrown)
        Button {
          picking = true
        } label: {
          row(green: false) {
            Text(machine.name).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Machine: \(machine.name). Change")
      }
      .padding(.bottom, 4)
      .onAppear { if let focusOnAppear { focused = focusOnAppear } }
      .onChange(of: workout.machine) { _, _ in if commit == nil { draft = nil } }
      .sheet(isPresented: $picking) { machinePicker }
    }
  }

  private func numberRow(
    _ setting: Machine.Setting, title: String, value: Double?, crown: Binding<Double>
  ) -> some View {
    let number = value.map { Int($0) }
    let green = focused == setting
    return row(green: green) {
      stepButton(setting, by: -1)
      // One line, "Incline 6", so the two number rows fit under the head.
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        Text(number.map(String.init) ?? "—")
          .font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
          .foregroundStyle(number == nil ? .secondary : .primary)
      }
      .frame(maxWidth: .infinity)
      stepButton(setting, by: 1)
    }
    .focusable()
    .focused($focused, equals: setting)
    .digitalCrownRotation(
      crown, from: Double(Machine.range.lowerBound), through: Double(Machine.range.upperBound), by: 1,
      sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true
    )
    .onTapGesture { focused = setting }
    // The Crown rests on the shown number, or on the machine's last one while it reads "—".
    .onChange(of: focused) { _, now in
      if now == setting { crown.wrappedValue = Double(number ?? start(setting)) }
    }
    .onChange(of: crown.wrappedValue) { _, turned in
      guard focused == setting else { return }
      let next = Machine.clamp(Int(turned.rounded()))
      // Resting the Crown on "—"'s start when the row takes it is no step; the first detent lands on start.
      if number == nil {
        let first = start(setting)
        guard next != first else { return }
        set(setting, to: first)
        crown.wrappedValue = Double(first)
      } else if next != number {
        set(setting, to: next)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(number.map { "\(title) \($0)" } ?? "\(title) not set")
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment: step(setting, by: 1)
      case .decrement: step(setting, by: -1)
      @unknown default: break
      }
    }
  }

  /// Where the first step from "—" lands: the machine's last value in any workout, else 0 or 1.
  private func start(_ setting: Machine.Setting) -> Int {
    Machine.step(nil, by: 1, last: shown.flatMap { workout.lastSetting(setting, on: $0.name) }, setting: setting)
  }

  private func step(_ setting: Machine.Setting, by delta: Int) {
    let value = setting == .incline ? shown?.incline : shown?.intensity
    let next =
      value == nil ? start(setting) : Machine.step(value.map { Int($0) }, by: delta, last: nil, setting: setting)
    set(setting, to: next)
    if setting == .incline { inclineCrown = Double(next) } else { intensityCrown = Double(next) }
  }

  private func set(_ setting: Machine.Setting, to value: Int) {
    guard var machine = shown else { return }
    switch setting {
    case .incline: machine.incline = Double(value)
    case .intensity: machine.intensity = Double(value)
    }
    draft = machine
    let at = Date()
    draftAt = at
    commit?.cancel()
    commit = Task {
      try? await Task.sleep(for: Self.settle)
      guard !Task.isCancelled else { return }
      take(machine, at: at)
    }
  }

  private func take(_ machine: Machine, at: Date = Date()) {
    commit?.cancel()
    commit = nil
    workout.setMachine(machine, at: at)
    draft = nil
    WKInterfaceDevice.current().play(.success)
  }

  private func stepButton(_ setting: Machine.Setting, by delta: Int) -> some View {
    Button {
      step(setting, by: delta)
      focused = setting
      WKInterfaceDevice.current().play(.click)
    } label: {
      Image(systemName: delta < 0 ? "minus" : "plus")
        .font(.title3.bold())
        .frame(width: 44, height: 44)
        .background(Color.secondary.opacity(0.3), in: Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(delta < 0 ? "One lower" : "One higher")
  }

  /// A row of the rows: full width, at least 44 pt, outlined green while it has the Crown (as the count page's).
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

  /// The machines as big tiles, one tap picks: a new machine starts with no numbers.
  private var machinePicker: some View {
    ScrollView {
      VStack(spacing: 6) {
        ForEach(Machine.names, id: \.self) { name in
          let picked = shown?.name == name
          Button {
            picking = false
            if !picked {
              take(Machine(name: name))
            } else if commit != nil, let draft {
              take(draft, at: draftAt ?? Date())
            }
          } label: {
            Text(name).font(.headline)
              .frame(maxWidth: .infinity, minHeight: 44)
              .foregroundStyle(picked ? Color.black : .primary)
              .background(picked ? Color.green : Color.secondary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(picked ? .isSelected : [])
        }
      }
    }
  }
}
