// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  Watch-face complication (issue #10): a static accessory widget whose only job is to open the watch app with
//  one tap, so a set can be started without digging through the app list.

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
  var body: some Widget { LaunchComplication() }
}
