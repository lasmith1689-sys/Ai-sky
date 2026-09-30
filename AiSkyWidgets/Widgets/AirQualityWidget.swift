import AiSkyKit
import SwiftUI
import WidgetKit

struct AirQualityWidget: Widget {
    let kind = "AiSkyAirQuality"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectLocationIntent.self, provider: WeatherTimelineProvider(style: .slow)) { entry in
            WidgetEnvironmentBridge { AirQualityWidgetView(entry: entry) }
        }
        .configurationDisplayName("Air Quality")
        .description("Air Quality Index and the pollutant driving it.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .accessoryCircular) {
    AirQualityWidget()
} timeline: {
    WeatherEntry.preview()
}
