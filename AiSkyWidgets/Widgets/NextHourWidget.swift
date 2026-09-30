import AiSkyKit
import SwiftUI
import WidgetKit

/// Dark Sky style "Rain starting in 12 min" with the minute-by-minute graph.
struct NextHourWidget: Widget {
    let kind = "AiSkyNextHour"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectLocationIntent.self, provider: WeatherTimelineProvider(style: .nextHour)) { entry in
            WidgetEnvironmentBridge { NextHourWidgetView(entry: entry) }
        }
        .configurationDisplayName("Next Hour")
        .description("Down-to-the-minute rain and snow for the next hour.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .systemMedium) {
    NextHourWidget()
} timeline: {
    WeatherEntry.preview()
}
