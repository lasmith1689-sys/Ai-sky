import AiSkyKit
import Charts
import SwiftUI
import WidgetKit

/// Precip-style rainfall totals: how much fell and how much is coming.
struct PrecipitationWidget: Widget {
    let kind = "AiSkyPrecipitation"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectLocationIntent.self, provider: WeatherTimelineProvider(style: .slow)) { entry in
            WidgetEnvironmentBridge { PrecipitationWidgetView(entry: entry) }
        }
        .configurationDisplayName("Rainfall")
        .description("Rain totals for the past day and week, and what's expected next.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

#Preview(as: .systemSmall) {
    PrecipitationWidget()
} timeline: {
    WeatherEntry.preview()
}
