// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  A set's plates on the wrist (story 086, #375; Igor: "weights on a side 10 25 35 45 … Them show full weight x2 +
//  65"): the phone's plate sheet (083) at a watch's size. The total over the bars, then the plates two across; a tap
//  puts one on each side, a press and hold takes one off. The checkmark keeps it, the close button does not.

import ExerciseCore
import SwiftUI
import WatchKit

struct WatchBarbellPage: View {
  @State private var load: BarbellLoad
  let onDone: (BarbellLoad) -> Void
  /// "Bells instead": back to the bell tiles, the plates dropped.
  let onBells: () -> Void
  @Environment(\.dismiss) private var dismiss

  init(load: BarbellLoad, onDone: @escaping (BarbellLoad) -> Void, onBells: @escaping () -> Void) {
    _load = State(initialValue: load)
    self.onDone = onDone
    self.onBells = onBells
  }

  var body: some View {
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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 2), spacing: 5) {
          ForEach(BarbellLoad.plateSizes, id: \.self) { plate in plateTile(plate) }
        }
        Button {
          onBells()
          dismiss()
        } label: {
          Text("Bells instead").frame(maxWidth: .infinity)
        }
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

  /// Not a Button: a Button's tap fires on the release of a press and hold too, which would put the plate back
  /// (as the phone's, 083).
  private func plateTile(_ plate: Int) -> some View {
    let count = load.count(of: plate)
    return VStack(spacing: 0) {
      Text("\(plate)").font(.title3.bold()).monospacedDigit()
      Text(count == 0 ? " " : "×\(count)").font(.caption.bold()).monospacedDigit()
    }
    .frame(maxWidth: .infinity, minHeight: 48)
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
