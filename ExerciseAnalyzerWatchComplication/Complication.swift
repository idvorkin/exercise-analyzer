// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Watch-face complication (issue #10): a static accessory widget whose only job is to open the watch app with
//  one tap, so a set can be started without digging through the app list.

import ExerciseCore
import SwiftUI
import WidgetKit

struct LaunchEntry: TimelineEntry {
  let date: Date
}

struct LaunchProvider: TimelineProvider {
  func placeholder(in context: Context) -> LaunchEntry { LaunchEntry(date: .now) }
  func getSnapshot(in context: Context, completion: @escaping (LaunchEntry) -> Void) { completion(LaunchEntry(date: .now)) }
  func getTimeline(in context: Context, completion: @escaping (Timeline<LaunchEntry>) -> Void) {
    completion(Timeline(entries: [LaunchEntry(date: .now)], policy: .never))
  }
}

struct LaunchComplicationView: View {
  @Environment(\.widgetFamily) private var family
  let entry: LaunchEntry

  var body: some View {
    switch family {
    case .accessoryInline:
      Label("Exercise Analyzer", systemImage: "figure.strengthtraining.traditional")
    case .accessoryCorner:
      Image(systemName: "figure.strengthtraining.traditional")
        .font(.title3)
        .widgetLabel { Text("Analyzer") }
    default:
      ZStack {
        AccessoryWidgetBackground()
        Image(systemName: "figure.strengthtraining.traditional").font(.title2)
      }
    }
  }
}

struct LaunchComplication: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "com.idvorkin.exerciseanalyzer.launch", provider: LaunchProvider()) { entry in
      LaunchComplicationView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Exercise Analyzer")
    .description("Opens the app to start a set.")
    .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
  }
}

@main
struct ComplicationBundle: WidgetBundle {
  var body: some Widget {
    LaunchComplication()
    FaceComplication()
  }
}

//  The set on the face (story 043, #70): reads the FaceState the watch app mirrors into the App Group on
//  transitions (and at most every 10 s mid-set) and reloads this timeline. The timer ticks by itself from
//  `startedAt`, so the timeline is one entry with policy `.never`. Never driven by
//  `transferCurrentComplicationUserInfo` (50 a day would die in the first set).

struct FaceEntry: TimelineEntry {
  let date: Date
  let face: FaceState?
}

struct FaceProvider: TimelineProvider {
  func placeholder(in context: Context) -> FaceEntry {
    FaceEntry(
      date: .now,
      face: FaceState(
        recording: true, reps: 6, startedAt: .now.addingTimeInterval(-42), exercise: "Kettlebell Swing",
        updatedAt: .now))
  }

  func getSnapshot(in context: Context, completion: @escaping (FaceEntry) -> Void) {
    completion(FaceEntry(date: .now, face: loadFace() ?? placeholder(in: context).face))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<FaceEntry>) -> Void) {
    completion(Timeline(entries: [FaceEntry(date: .now, face: loadFace())], policy: .never))
  }

  /// The widget extension cannot use WCSession: the shared container is its only pipe.
  private func loadFace() -> FaceState? {
    guard let dir = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: FaceState.groupID),
      let data = try? Data(contentsOf: dir.appendingPathComponent(FaceState.fileName))
    else { return nil }
    return try? JSONDecoder().decode(FaceState.self, from: data)
  }
}

struct FaceComplicationView: View {
  @Environment(\.widgetFamily) private var family
  let entry: FaceEntry

  private var face: FaceState { entry.face ?? FaceState() }

  /// "6 · Kettlebell Swing", or nil when there is no finished set yet.
  private var lastSetLine: String? {
    guard let last = face.lastSet else { return nil }
    return "\(last.reps) · \(last.exercise)"
  }

  var body: some View {
    switch family {
    case .accessoryRectangular:
      if face.recording {
        HStack {
          Text("● REC").foregroundStyle(.red)
          if let startedAt = face.startedAt { Text(startedAt, style: .timer) }
          Spacer()
          Text("\(face.reps) reps")
        }
      } else {
        HStack {
          Image(systemName: "figure.strengthtraining.traditional")
          if let line = lastSetLine {
            Text(line)
          } else {
            Text("Exercise Analyzer")
          }
        }
      }
    case .accessoryCircular:
      ZStack {
        AccessoryWidgetBackground()
        VStack(spacing: 0) {
          Text("\(face.recording ? face.reps : (face.lastSet?.reps ?? 0))")
            .font(.headline)
          if face.recording {
            Circle().fill(.red).frame(width: 6, height: 6)
          } else {
            Image(systemName: "figure.strengthtraining.traditional").font(.caption2)
          }
        }
      }
    case .accessoryCorner:
      Image(systemName: "figure.strengthtraining.traditional")
        .font(.title3)
        .widgetLabel {
          if face.recording { Text("REC") } else { Text("Analyzer") }
        }
    default:  // .accessoryInline and anything later families bring
      if face.recording {
        if let startedAt = face.startedAt {
          Text("REC ") + Text(startedAt, style: .timer) + Text(" · \(face.reps)")
        } else {
          Text("REC · \(face.reps)")
        }
      } else {
        Text(lastSetLine ?? "Exercise Analyzer")
      }
    }
  }
}

struct FaceComplication: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: FaceState.widgetKind, provider: FaceProvider()) { entry in
      FaceComplicationView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Current set")
    .description("The recording set on the face: timer and count.")
    .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline])
  }
}
