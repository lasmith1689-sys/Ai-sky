import AiSkyKit
import SwiftUI
import WidgetKit

struct AirQualityWidget: Widget {
    let kind = "AiSkyAirQuality"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectLocationIntent.self, provider: WeatherTimelineProvider(style: .slow)) { entry in
            AirQualityWidgetView(entry: entry)
        }
        .configurationDisplayName("Air Quality")
        .description("Air Quality Index and the pollutant driving it.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct AirQualityWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeatherEntry

    var body: some View {
        content
            .widgetURL(entry.deepLink(section: "airQuality"))
            .containerBackground(for: .widget) {
                WidgetBackground(entry: entry)
            }
    }

    @ViewBuilder
    private var content: some View {
        let scale = entry.settings.aqiScale
        if let location = entry.location, let airQuality = entry.snapshot?.airQuality, let value = airQuality.index(for: scale) {
            let level = scale.level(for: value)
            let number = "\(Int(value.rounded()))"
            switch family {
            case .accessoryInline:
                Label("\(scale.shortName) \(number) · \(level.name)", systemImage: "aqi.medium")
            case .accessoryCircular:
                Gauge(value: min(value, scale.gaugeMaximum), in: 0...scale.gaugeMaximum) {
                    Text(scale.shortName)
                } currentValueLabel: {
                    Text(number)
                }
                .gaugeStyle(.accessoryCircular)
                .tint(Gradient(colors: AQILevel.levels(for: scale).map(Palette.aqi)))
                .widgetAccentable()
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Label("Air Quality", systemImage: "aqi.medium")
                        .font(.headline)
                        .widgetAccentable()
                    Text("\(number) · \(level.name)")
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if let pollutant = airQuality.primaryPollutant(for: scale) {
                        Text("\(pollutant.symbol) · \(location.name)")
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                let t = entry.tokens
                VStack(alignment: .leading, spacing: 3) {
                    WidgetLocationName(location: location)
                        .font(t.look == .liquid ? .caption.weight(.semibold) : t.font(.textStrong, 12))
                        .widgetAccentable()
                    if t.look == .liquid {
                        Text("AIR QUALITY")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(t.ink2)
                    } else {
                        Text("Air Quality")
                            .lookLabel(t, size: 9, color: t.ink2)
                    }
                    Text(number)
                        .font(t.look == .liquid ? .system(size: 40, weight: .semibold, design: .rounded) : t.font(.display, 40))
                        .widgetAccentable()
                    Text(level.name)
                        .font(t.look == .liquid ? .caption.weight(.semibold) : t.font(.textStrong, 12))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    ScaleBar(colors: AQILevel.levels(for: scale).map(Palette.aqi), position: min(1, value / scale.gaugeMaximum))
                    if let pollutant = airQuality.primaryPollutant(for: scale) {
                        Text("Primary: \(pollutant.symbol)")
                            .font(t.look == .liquid ? .caption2 : t.font(.text, 11))
                            .foregroundStyle(t.ink2)
                    }
                }
                .foregroundStyle(t.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else {
            WidgetEmptyView(entry: entry)
        }
    }
}

/// Gradient bar with a marker (duplicated from the app to keep the extension self-contained).
private struct ScaleBar: View {
    let colors: [Color]
    let position: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(.black.opacity(0.4), lineWidth: 1))
                    .frame(width: 8, height: 8)
                    .offset(x: max(0, min(proxy.size.width - 8, proxy.size.width * position - 4)))
            }
        }
        .frame(height: 5)
    }
}

#Preview(as: .accessoryCircular) {
    AirQualityWidget()
} timeline: {
    WeatherEntry.preview()
}
