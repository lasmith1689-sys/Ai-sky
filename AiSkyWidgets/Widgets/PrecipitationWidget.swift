import AiSkyKit
import Charts
import SwiftUI
import WidgetKit

/// Precip-style rainfall totals: how much fell and how much is coming.
struct PrecipitationWidget: Widget {
    let kind = "AiSkyPrecipitation"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectLocationIntent.self, provider: WeatherTimelineProvider(style: .slow)) { entry in
            PrecipitationWidgetView(entry: entry)
        }
        .configurationDisplayName("Rainfall")
        .description("Rain totals for the past day and week, and what's expected next.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct PrecipitationWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeatherEntry

    var body: some View {
        content
            .widgetURL(entry.deepLink(section: "precipitation"))
            .containerBackground(for: .widget) {
                WidgetBackground(entry: entry)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot, let location = entry.location {
            let totals = PrecipitationTotals.compute(for: snapshot, now: entry.date)
            let formatter = entry.formatter
            let t = entry.tokens
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Label("Rainfall", systemImage: "drop.fill")
                        .font(.headline)
                        .widgetAccentable()
                    Text("Past 24h \(amount(totals.past24Hours, formatter))")
                        .font(.caption.weight(.semibold))
                    Text("Next 24h \(amount(totals.next24Hours, formatter))")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .systemMedium:
                HStack(spacing: 12) {
                    stats(totals: totals, formatter: formatter, location: location)
                    VStack(alignment: .leading, spacing: 2) {
                        Chart(Array(totals.dailyBars.suffix(10))) { bar in
                            BarMark(
                                // Month/day labels are unique within the window (weekday names repeat).
                                x: .value("Day", formatter.monthDay(bar.date, timeZone: snapshot.timeZone)),
                                y: .value("Amount", formatter.precipitationValue(bar.total))
                            )
                            .foregroundStyle(bar.forecast > bar.observed ? t.rain.opacity(0.45) : t.rain)
                        }
                        .chartYAxis(.hidden)
                        .chartXAxis(.hidden)
                        .widgetAccentable()
                        Text("Daily totals · lighter = forecast")
                            .font(t.look == .liquid ? .system(size: 9) : t.font(.text, 9))
                            .foregroundStyle(t.ink2)
                    }
                }
                .foregroundStyle(t.ink)
            default:
                stats(totals: totals, formatter: formatter, location: location)
                    .foregroundStyle(t.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else {
            WidgetEmptyView(entry: entry)
        }
    }

    private func stats(totals: PrecipitationTotals, formatter: WeatherFormatter, location: WeatherLocation) -> some View {
        let t = entry.tokens
        return VStack(alignment: .leading, spacing: 3) {
            WidgetLocationName(location: location)
                .font(t.look == .liquid ? .caption.weight(.semibold) : t.font(.textStrong, 12))
                .widgetAccentable()
            stat("Past 24 hrs", amount(totals.past24Hours, formatter), prominent: true)
            stat("Past 7 days", amount(totals.past7Days, formatter))
            stat("Next 24 hrs", amount(totals.next24Hours, formatter))
            Spacer(minLength: 0)
            if let last = totals.lastPrecipitation {
                Text(lastText(last.date))
                    .font(t.look == .liquid ? .system(size: 10) : t.font(.text, 10))
                    .foregroundStyle(t.ink2)
            }
        }
    }

    private func stat(_ title: String, _ value: String, prominent: Bool = false) -> some View {
        let t = entry.tokens
        return VStack(alignment: .leading, spacing: 0) {
            if t.look == .liquid {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(t.ink2)
                Text(value)
                    .font(prominent ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
            } else {
                Text(title)
                    .lookLabel(t, size: 9, color: t.ink2)
                Text(value)
                    .font(t.font(prominent ? .display : .textStrong, prominent ? 22 : 15))
            }
        }
    }

    private func amount(_ millimeters: Double?, _ formatter: WeatherFormatter) -> String {
        millimeters.map { formatter.precipitation($0) } ?? "--"
    }

    private func lastText(_ date: Date) -> String {
        let hours = entry.date.timeIntervalSince(date) / 3600
        if hours < 1 { return "Raining recently" }
        if hours < 48 { return "Last rain \(Int(hours)) hr ago" }
        return "Last rain \(Int(hours / 24)) days ago"
    }
}

#Preview(as: .systemSmall) {
    PrecipitationWidget()
} timeline: {
    WeatherEntry.preview()
}
