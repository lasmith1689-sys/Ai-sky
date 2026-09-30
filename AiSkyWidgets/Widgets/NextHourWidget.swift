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
            .widgetURL(entry.deepLink(section: "nextHour"))
            .containerBackground(for: .widget) {
                WidgetBackground(entry: entry)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot, let location = entry.location {
            let summary = entry.nextHour
            let t = entry.tokens
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
                            .font(t.look == .liquid ? .subheadline.weight(.semibold) : t.font(.textStrong, 14))
                            .widgetAccentable()
                        Spacer()
                        if t.look == .liquid {
                            Text("Next Hour")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(t.ink2)
                        } else {
                            Text("Next Hour")
                                .lookLabel(t, size: 10, color: t.ink2)
                        }
                    }
                    Text(summary.text)
                        .font(t.look == .liquid ? .subheadline.weight(.semibold) : t.font(.textStrong, 14))
                        .foregroundStyle(summary.isPrecipitationExpected ? t.rainText : t.ink)
                        .lineLimit(2)
                    if let nextHour = snapshot.nextHour, summary.state != .unavailable {
                        if t.look == .liquid {
                            MinutePrecipitationChart(forecast: nextHour, now: entry.date, showsGuides: summary.isPrecipitationExpected, showsAxis: true)
                        } else {
                            MinuteBars(forecast: nextHour, now: entry.date, wetColor: t.rain, dryColor: t.track)
                                .widgetAccentable()
                        }
                    }
                }
                .foregroundStyle(t.ink)
            default:
                VStack(alignment: .leading, spacing: 4) {
                    WidgetLocationName(location: location)
                        .font(t.look == .liquid ? .caption.weight(.semibold) : t.font(.textStrong, 12))
                        .widgetAccentable()
                    Image(systemName: symbol(summary))
                        .symbolRenderingMode(t.look == .liquid ? .multicolor : .monochrome)
                        .foregroundStyle(summary.isPrecipitationExpected ? t.rainText : t.ink2)
                        .font(.title2)
                    Text(summary.shortText)
                        .font(t.look == .liquid ? .subheadline.weight(.semibold) : t.font(.textStrong, 14))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if let nextHour = snapshot.nextHour, summary.state != .unavailable {
                        if t.look == .liquid {
                            MinutePrecipitationChart(forecast: nextHour, now: entry.date, showsGuides: false, showsAxis: false)
                                .frame(height: 36)
                        } else {
                            MinuteBars(forecast: nextHour, now: entry.date, wetColor: t.rain, dryColor: t.track)
                                .frame(height: 30)
                                .widgetAccentable()
                        }
                    }
                }
                .foregroundStyle(t.ink)
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
