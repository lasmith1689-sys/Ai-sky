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
                            .foregroundStyle(bar.forecast > bar.observed ? Palette.rain.opacity(0.45) : Palette.rain)
                        }
                        .chartYAxis(.hidden)
                        .chartXAxis(.hidden)
                        Text("Daily totals · lighter = forecast")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .foregroundStyle(.white)
            default:
                stats(totals: totals, formatter: formatter, location: location)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else {
            WidgetEmptyView(entry: entry)
        }
    }

    private func stats(totals: PrecipitationTotals, formatter: WeatherFormatter, location: WeatherLocation) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            WidgetLocationName(location: location)
                .font(.caption.weight(.semibold))
            stat("Past 24 hrs", amount(totals.past24Hours, formatter), prominent: true)
            stat("Past 7 days", amount(totals.past7Days, formatter))
            stat("Next 24 hrs", amount(totals.next24Hours, formatter))
            Spacer(minLength: 0)
            if let last = totals.lastPrecipitation {
                Text(lastText(last.date))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private func stat(_ title: String, _ value: String, prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
            Text(value)
                .font(prominent ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
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
