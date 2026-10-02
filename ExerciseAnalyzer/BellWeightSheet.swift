// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  The bell's weight for a set (story 066, #102; Igor picked "you tap it" on 2026-10-01): one tap on a big
//  button in the competition bell's own colour saves it; "Other" steps by 2 kg for a weight off the code.

import SwiftUI

struct BellWeightSheet: View {
  /// What the set shows now, its own or carried from the set before; nil when nothing.
  let kg: Int?
  /// The weight is the set before's, not this set's own: there is nothing of its own to clear.
  let inherited: Bool
  let onSave: (Int?) -> Void
  @State private var other: Int?
  @Environment(\.dismiss) private var dismiss

  init(kg: Int?, inherited: Bool, onSave: @escaping (Int?) -> Void) {
    self.kg = kg
    self.inherited = inherited
    self.onSave = onSave
    _other = State(initialValue: kg.flatMap { Self.code.map(\.kg).contains($0) ? nil : $0 })
  }

  /// The competition colour code (the detector's map, `BellColor`): 8 pink … 32 red.
  private static let code: [(kg: Int, color: Color)] = [
    (8, .pink), (12, .blue), (16, .yellow), (20, .purple), (24, .green), (28, .orange), (32, .red),
  ]

  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
          ForEach(Self.code, id: \.kg) { bell in
            Button { save(bell.kg) } label: {
              Text("\(bell.kg)").font(.title2.bold()).monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(bell.color.opacity(bell.kg == kg ? 0.55 : 0.22), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(bell.kg == kg ? bell.color : .clear, lineWidth: 3))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(bell.kg) kilograms")
            .accessibilityAddTraits(bell.kg == kg ? .isSelected : [])
          }
          Button { other = other ?? kg ?? 36 } label: {
            Text("Other").font(.headline)
              .frame(maxWidth: .infinity, minHeight: 64)
              .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
          }
          .buttonStyle(.plain)
        }
        if let value = other {
          HStack(spacing: 20) {
            step("minus", value: value, by: -2)
            Text("\(value) kg").font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
              .frame(minWidth: 120)
            step("plus", value: value, by: 2)
          }
          Button { save(value) } label: {
            Text("Save \(value) kg").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
          }
          .buttonStyle(.borderedProminent).tint(.green)
        }
        if kg != nil && !inherited {
          Button("No weight", role: .destructive) { save(nil) }
            .frame(minHeight: 44)
        }
        Spacer(minLength: 0)
      }
      .padding()
      .navigationTitle("The bell's weight")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
    .presentationDetents([.medium, .large])
  }

  private func save(_ value: Int?) {
    onSave(value)
    dismiss()
  }

  private func step(_ symbol: String, value: Int, by delta: Int) -> some View {
    Button { other = min(max(value + delta, 2), 100) } label: {
      Image(systemName: symbol).font(.title.bold()).frame(width: 60, height: 60)
        .background(Color.secondary.opacity(0.2), in: Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(delta < 0 ? "Two kilograms less" : "Two kilograms more")
  }
}
