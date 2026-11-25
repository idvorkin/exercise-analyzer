// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  A set's plates on the wrist (story 086, #375; Igor: "weights on a side 10 25 35 45 … Them show full weight x2 +
//  65"): the phone's plate sheet (083) at a watch's size. The total over the bars, then the plates one per row; a
//  tap on a plate puts one on each side, the "−" beside it (or a press and hold) takes one off, and "Empty bar"
//  takes them all off (ea-71t, as the phone's #387). The checkmark keeps it, the close button does not.

import ExerciseCore
import SwiftUI
import WatchKit

struct WatchBarbellPage: View {
  @State private var load: BarbellLoad
  /// The screenshot rung's setByHandBarbellEnd: open scrolled to the bottom (ea-71t).
  let scrollsToEnd: Bool
  let onDone: (BarbellLoad) -> Void
  /// "Bells instead": back to the bell tiles, the plates dropped.
  let onBells: () -> Void
  @Environment(\.dismiss) private var dismiss

  init(
    load: BarbellLoad, scrollsToEnd: Bool = false, onDone: @escaping (BarbellLoad) -> Void,
    onBells: @escaping () -> Void
  ) {
    _load = State(initialValue: load)
    self.scrollsToEnd = scrollsToEnd
    self.onDone = onDone
    self.onBells = onBells
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(spacing: 5) {
          VStack(spacing: 0) {
            Text("\(load.totalLb) lb").font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
            Text(load.sideLabel).font(.caption).foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel(SetWeight.barbell(load).spoken)
          HStack(spacing: 5) {
            ForEach(BarKind.allCases, id: \.self) { bar in barTile(bar) }
          }
          // One plate a row, its "−" beside it (ea-71t): two across left no room for a 44 pt "−" of its own, and
          // a row of them under the plates fell below a 40 mm face's first screen.
          ForEach(BarbellLoad.plateSizes, id: \.self) { plate in
            HStack(spacing: 5) {
              minusButton(plate)
              plateTile(plate)
            }
          }
          if !load.plates.isEmpty {
            Button {
              load.empty()
              WKInterfaceDevice.current().play(.directionDown)
            } label: {
              Text("Empty bar").frame(maxWidth: .infinity)
            }
            .accessibilityHint("Takes every plate off")
          }
          Button {
            onBells()
            dismiss()
          } label: {
            Text("Bells instead").frame(maxWidth: .infinity)
          }
          .id("plates-end")
        }
      }
      .onAppear {
        guard scrollsToEnd else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo("plates-end", anchor: .bottom) }
      }
    }
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button {
          onDone(load)
          dismiss()
        } label: {
          Image(systemName: "checkmark")
        }
        .tint(.green)
        .accessibilityLabel("Save the plates")
      }
    }
  }

  private func barTile(_ bar: BarKind) -> some View {
    let picked = load.bar == bar
    return Button {
      load.bar = bar
      WKInterfaceDevice.current().play(.click)
    } label: {
      VStack(spacing: 0) {
        Text("\(bar.lb)").font(.headline).monospacedDigit()
        Text("bar").font(.caption2)
      }
      .frame(maxWidth: .infinity, minHeight: 44)
      .foregroundStyle(picked ? Color.black : .primary)
      .background(picked ? Color.green : Color.secondary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(bar.name), \(bar.lb) pounds")
    .accessibilityAddTraits(picked ? .isSelected : [])
  }

  /// Takes one `plate` off each side (ea-71t): a sibling of the plate, never inside its tap area; there but faded
  /// and inert while none is on, so the rows never jump.
  private func minusButton(_ plate: Int) -> some View {
    let count = load.count(of: plate)
    return Button {
      load.remove(plate)
      WKInterfaceDevice.current().play(.directionDown)
    } label: {
      Image(systemName: "minus").font(.title3.bold())
        .frame(width: 44, height: 44)
        .background(Color.secondary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
    .opacity(count > 0 ? 1 : 0.3)
    .disabled(count == 0)
    .accessibilityHidden(count == 0)
    .accessibilityLabel("One \(plate) pound plate off each side")
  }

  /// Not a Button: a Button's tap fires on the release of a press and hold too, which would put the plate back
  /// (as the phone's, 083).
  private func plateTile(_ plate: Int) -> some View {
    let count = load.count(of: plate)
    return HStack(spacing: 6) {
      Text("\(plate)").font(.title3.bold()).monospacedDigit()
      if count > 0 { Text("×\(count)").font(.caption.bold()).monospacedDigit() }
    }
    .frame(maxWidth: .infinity, minHeight: 44)
    .background(Color.secondary.opacity(count > 0 ? 0.45 : 0.2), in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(count > 0 ? Color.white : .clear, lineWidth: 2))
    .contentShape(RoundedRectangle(cornerRadius: 12))
    .onTapGesture {
      load.add(plate)
      WKInterfaceDevice.current().play(.click)
    }
    .onLongPressGesture(minimumDuration: 0.4) {
      load.remove(plate)
      WKInterfaceDevice.current().play(.directionDown)
    }
    .accessibilityElement()
    .accessibilityLabel("\(plate) pound plates")
    .accessibilityValue("\(count) per side")
    .accessibilityAddTraits(.isButton)
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
