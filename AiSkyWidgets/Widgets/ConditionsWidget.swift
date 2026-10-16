import AiSkyKit
import SwiftUI
import WidgetKit

/// Current conditions for any saved place, on the Home Screen and Lock Screen.
struct ConditionsWidget: Widget {
    let kind = "AiSkyConditions"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectLocationIntent.self, provider: WeatherTimelineProvider(style: .conditions)) { entry in
            WidgetEnvironmentBridge { ConditionsWidgetView(entry: entry) }
        }
        .configurationDisplayName("Conditions")
        .description("Temperature, feels-like, today's range and what's coming next.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .systemSmall) {
    ConditionsWidget()
} timeline: {
    WeatherEntry.preview()
}

#Preview(as: .accessoryRectangular) {
    ConditionsWidget()
} timeline: {
    WeatherEntry.preview()
}
