// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Watch mode: the phone sits on a tripod and is driven from the wrist, so its screen shows what is readable
//  from across the room: the rep count in huge digits, the in-frame hint in red when the lifter is out, the
//  elapsed time and the exercise; VIEWFINDER in place of the count while framing (047). Nothing else. Only while
//  the camera is up (the session refuses it otherwise and
//  leaves it with the set, #36). Long-press anywhere to leave (a stray tap must not).

import ExerciseCore
import SwiftUI

struct WatchModeView: View {
  @ObservedObject var session: VideoPoseSession

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      VStack(spacing: 12) {
        Spacer()
        if session.viewfinder {
          // Framing from the wrist's Preview, not recording: the count names the state, as on the HUD (047, #144).
          Text("VIEWFINDER")
            .font(.system(size: 220, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.2).lineLimit(1)
            .foregroundStyle(.white)
        } else {
          Text("\(session.reps.count)")
            .font(.system(size: 220, weight: .bold, design: .rounded).monospacedDigit())
            .minimumScaleFactor(0.4).lineLimit(1)
            .foregroundStyle(.white)
          Text(session.reps.count == 1 ? "rep" : "reps").font(.title).foregroundStyle(.gray)
        }
        if session.paused {
          Text("PAUSED")
            .font(.system(size: 40, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 24).padding(.vertical, 10)
            .background(Color.orange, in: RoundedRectangle(cornerRadius: 16))
            .minimumScaleFactor(0.5).lineLimit(1)
        }
        if !session.frameStatus.inFrame {
          Text(session.frameStatus.hint.uppercased())
            .font(.system(size: 40, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 24).padding(.vertical, 10)
            .background(Color.red, in: RoundedRectangle(cornerRadius: 16))
            .minimumScaleFactor(0.5).lineLimit(1)
        } else {
          Text("IN FRAME").font(.title2.bold()).foregroundStyle(.green)
        }
        Text(elapsed).font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(.white)
        Text(session.exercise.definition.name).font(.title3).foregroundStyle(.gray)
        Spacer()
        Button {
          session.setWatchMode(false, from: "phone_button")
        } label: {
          Label("Leave watch mode", systemImage: "xmark.circle")
            .font(.headline)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(Color.white.opacity(0.15), in: Capsule())
            .foregroundStyle(.white)
        }
        Text("Or double-tap anywhere, or press and hold").font(.footnote).foregroundStyle(.gray).padding(.bottom, 16)
      }
      .padding(.horizontal, 24)
      .multilineTextAlignment(.center)
    }
    .contentShape(Rectangle())
    // Three ways out: the button, a double tap, or a half-second hold. A single tap does nothing on purpose.
    .onTapGesture(count: 2) { session.setWatchMode(false, from: "phone_doubletap") }
    .onLongPressGesture(minimumDuration: 0.5) { session.setWatchMode(false, from: "phone_longpress") }
    .statusBarHidden(true)
    .preferredColorScheme(.dark)
  }

  private var elapsed: String {
    let total = Int(session.duration)
    return String(format: "%d:%02d", total / 60, total % 60)
  }
}
