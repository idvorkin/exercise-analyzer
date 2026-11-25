// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  A barbell set's weight as plates (story 083, #377; Igor, 2026-11-24: "That can be my barbell weight input"):
//  pick the bar, tap a plate to put one on each side, "−" under it (or a press and hold) to take one off, at most
//  8 a side (#387); the total is added up.

import ExerciseCore
import SwiftUI

struct BarbellPicker: View {
  @Binding var load: BarbellLoad

  var body: some View {
    VStack(spacing: 14) {
      Picker("Bar", selection: $load.bar) {
        // Three bars since #375: the short names fit a segment each.
        ForEach(BarKind.allCases, id: \.self) { bar in Text(bar.short).tag(bar).accessibilityLabel(bar.name) }
      }
      .pickerStyle(.segmented)
      // The bar as it is loaded (#388), changing with every tap.
      LoadedBarView(load: load).frame(height: 70)
      VStack(spacing: 2) {
        Text("\(load.totalLb) lb").font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
        Text(load.sideLabel).font(.headline).foregroundStyle(.secondary)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(SetWeight.barbell(load).spoken)
      HStack(spacing: 10) {
        ForEach(BarbellLoad.plateSizes, id: \.self) { plate in
          // A "−" under each plate on the bar (#387): the press and hold alone was not found, and slid into a
          // scroll. A sibling of the plate, never inside its tap area.
          VStack(spacing: 6) {
            plateButton(plate)
            minusButton(plate)
          }
        }
      }
      if load.isFull {
        Text("The bar is full: \(BarbellLoad.maxPlatesPerSide) plates a side")
          .font(.footnote.bold()).foregroundStyle(.orange)
      }
      if !load.plates.isEmpty {
        Button("Empty bar") { load.empty() }
          .buttonStyle(.bordered).frame(minHeight: 44)
      }
      Text("Tap a plate to put one on each side; − takes one off.")
        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }
  }

  /// Takes one `plate` off each side; there, but faded out and inert, while none is on, so the row never jumps.
  private func minusButton(_ plate: Int) -> some View {
    let count = load.count(of: plate)
    return Button {
      load.remove(plate)
    } label: {
      Image(systemName: "minus").font(.title3.bold())
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
    }
    .buttonStyle(.plain)
    .opacity(count > 0 ? 1 : 0)
    .disabled(count == 0)
    .accessibilityHidden(count == 0)
    .accessibilityLabel("One \(plate) pound plate off each side")
  }

  /// One plate size: its weight, and how many are on each side. Not a Button: a Button's tap fires on the release
  /// of a press and hold too, which would put the plate back on.
  private func plateButton(_ plate: Int) -> some View {
    let count = load.count(of: plate)
    return VStack(spacing: 2) {
      Text("\(plate)").font(.title2.bold()).monospacedDigit()
      Text(count == 0 ? " " : "×\(count)").font(.subheadline.bold()).monospacedDigit()
    }
    .frame(maxWidth: .infinity, minHeight: 72)
    // In the plate's colour, as on the drawn bar (#388).
    .background(
      BarbellLoad.color(plate).opacity(count > 0 ? 0.5 : 0.2), in: RoundedRectangle(cornerRadius: 12)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12).stroke(count > 0 ? BarbellLoad.outline(plate) : .clear, lineWidth: 3)
    )
    .contentShape(RoundedRectangle(cornerRadius: 12))
    // A full side takes no more (#387): the plates dim until one comes off.
    .opacity(load.isFull ? 0.5 : 1)
    .onTapGesture { load.add(plate) }
    .onLongPressGesture(minimumDuration: 0.4) { load.remove(plate) }
    .accessibilityElement()
    .accessibilityLabel("\(plate) pound plates")
    .accessibilityValue("\(count) per side")
    .accessibilityAddTraits(.isButton)
    .accessibilityHint("Adds one to each side")
    .accessibilityAction { load.add(plate) }
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment: load.add(plate)
      case .decrement: load.remove(plate)
      @unknown default: break
      }
    }
  }
}

/// The plates alone, over the by-hand sheet: its weight row's "Bar".
struct BarbellSheet: View {
  @State private var load: BarbellLoad
  let onSave: (BarbellLoad) -> Void
  @Environment(\.dismiss) private var dismiss

  init(load: BarbellLoad, onSave: @escaping (BarbellLoad) -> Void) {
    _load = State(initialValue: load)
    self.onSave = onSave
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        BarbellPicker(load: $load)
        Button {
          onSave(load)
          dismiss()
        } label: {
          Text("Use \(load.totalLb) lb").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent).tint(.green)
        Spacer(minLength: 0)
      }
      .padding()
      .navigationTitle("The bar's weight")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
    .presentationDetents([.large])
  }
}
