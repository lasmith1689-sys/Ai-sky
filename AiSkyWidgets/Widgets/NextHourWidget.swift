import AiSkyKit
import SwiftUI
import WidgetKit

/// Dark Sky style "Rain starting in 12 min" with the minute-by-minute graph.
struct NextHourWidget: Widget {
    let kind = "AiSkyNextHour"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectLocationIntent.self, provider: WeatherTimelineProvider(style: .nextHour)) { entry in
            NextHourWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Hour")
        .description("Down-to-the-minute rain and snow for the next hour.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct NextHourWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeatherEntry

    var body: some View {
        content
            .widgetURL(entry.deepLink)
            .containerBackground(for: .widget) {
                WidgetBackground(entry: entry)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot, let location = entry.location {
            let summary = entry.nextHour
            switch family {
            case .accessoryInline:
                Label(summary.shortText, systemImage: symbol(summary))
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label(summary.shortText, systemImage: symbol(summary))
                        .font(.headline)
                        .widgetAccentable()
                        .lineLimit(1)
                    if let nextHour = snapshot.nextHour, summary.state != .unavailable {
                        MinutePrecipitationChart(forecast: nextHour, now: entry.date, showsGuides: false, showsAxis: false, tint: .primary)
                            .frame(height: 26)
                    } else {
                        WidgetLocationName(location: location)
                            .font(.caption)
                    }
                }
            case .systemMedium:
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        WidgetLocationName(location: location)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("Next Hour")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Text(summary.text)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    if let nextHour = snapshot.nextHour, summary.state != .unavailable {
                        MinutePrecipitationChart(forecast: nextHour, now: entry.date, showsGuides: summary.isPrecipitationExpected, showsAxis: true)
                    }
                }
                .foregroundStyle(.white)
            default:
                VStack(alignment: .leading, spacing: 4) {
                    WidgetLocationName(location: location)
                        .font(.caption.weight(.semibold))
                    Image(systemName: symbol(summary))
                        .symbolRenderingMode(.multicolor)
                        .font(.title2)
                    Text(summary.shortText)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if let nextHour = snapshot.nextHour, summary.state != .unavailable {
                        MinutePrecipitationChart(forecast: nextHour, now: entry.date, showsGuides: false, showsAxis: false)
                            .frame(height: 36)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else {
            WidgetEmptyView(entry: entry)
        }
    }

    private func symbol(_ summary: NextHourSummary) -> String {
        guard summary.isPrecipitationExpected else { return "umbrella" }
        switch summary.precipitationKind {
        case .snow: return "cloud.snow.fill"
        case .sleet, .mixed, .hail: return "cloud.sleet.fill"
        default: return summary.intensity >= .moderate ? "cloud.heavyrain.fill" : "cloud.rain.fill"
        }
    }
}

#Preview(as: .systemMedium) {
    NextHourWidget()
} timeline: {
    WeatherEntry.preview()
}
