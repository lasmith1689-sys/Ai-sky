import AiSkyKit
import SwiftUI
import WidgetKit

/// Current conditions for any saved place — Home Screen and Lock Screen.
struct ConditionsWidget: Widget {
    let kind = "AiSkyConditions"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectLocationIntent.self, provider: WeatherTimelineProvider(style: .conditions)) { entry in
            ConditionsWidgetView(entry: entry)
        }
        .configurationDisplayName("Conditions")
        .description("Temperature, feels-like, today's range and what's coming next.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct ConditionsWidgetView: View {
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
        if let snapshot = entry.snapshot, let location = entry.location, let current = entry.conditions {
            switch family {
            case .accessoryCircular:
                CircularConditionsView(entry: entry, current: current)
            case .accessoryRectangular:
                RectangularConditionsView(entry: entry, location: location, current: current)
            case .accessoryInline:
                Label {
                    Text("\(entry.formatter.temperature(current.temperature)) · Feels \(entry.formatter.temperature(current.apparentTemperature))")
                } icon: {
                    Image(systemName: current.condition.symbolName(isDaylight: current.isDaylight))
                }
            case .systemMedium:
                MediumConditionsView(entry: entry, snapshot: snapshot, location: location, current: current)
            case .systemLarge:
                LargeConditionsView(entry: entry, snapshot: snapshot, location: location, current: current)
            default:
                SmallConditionsView(entry: entry, location: location, current: current)
            }
        } else {
            WidgetEmptyView(entry: entry)
        }
    }
}

// MARK: Home Screen

private struct SmallConditionsView: View {
    let entry: WeatherEntry
    let location: WeatherLocation
    let current: CurrentConditions

    var body: some View {
        let formatter = entry.formatter
        VStack(alignment: .leading, spacing: 2) {
            WidgetLocationName(location: location)
                .font(.subheadline.weight(.semibold))
            Text(formatter.temperature(current.temperature))
                .font(.system(size: 44, weight: .light))
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            ConditionIcon(current.condition, isDaylight: current.isDaylight)
                .font(.title3)
            Text(current.condition.description)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            if entry.nextHour.isPrecipitationExpected {
                Text(entry.nextHour.shortText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.rain)
                    .lineLimit(1)
            } else {
                Text("Feels \(formatter.temperature(current.apparentTemperature))")
                    .font(.caption2.weight(.medium))
            }
            if let today = entry.today {
                Text("H:\(formatter.temperature(today.high)) L:\(formatter.temperature(today.low))")
                    .font(.caption2.weight(.medium))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct MediumConditionsView: View {
    let entry: WeatherEntry
    let snapshot: WeatherSnapshot
    let location: WeatherLocation
    let current: CurrentConditions

    var body: some View {
        let formatter = entry.formatter
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetLocationName(location: location)
                        .font(.subheadline.weight(.semibold))
                    Text(formatter.temperature(current.temperature))
                        .font(.system(size: 40, weight: .light))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    ConditionIcon(current.condition, isDaylight: current.isDaylight)
                        .font(.title3)
                    Text(current.condition.description)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text("Feels \(formatter.temperature(current.apparentTemperature))")
                        .font(.caption2)
                    if let today = entry.today {
                        Text("H:\(formatter.temperature(today.high)) L:\(formatter.temperature(today.low))")
                            .font(.caption2)
                    }
                }
            }
            if entry.nextHour.isPrecipitationExpected {
                Text(entry.nextHour.text)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            HStack(spacing: 0) {
                let hours = snapshot.upcomingHours(from: entry.date, limit: 6)
                ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                    WidgetHourColumn(hour: hour, formatter: formatter, timeZone: snapshot.timeZone, isFirst: index == 0)
                }
            }
        }
        .foregroundStyle(.white)
    }
}

private struct LargeConditionsView: View {
    let entry: WeatherEntry
    let snapshot: WeatherSnapshot
    let location: WeatherLocation
    let current: CurrentConditions

    var body: some View {
        let formatter = entry.formatter
        let days = snapshot.upcomingDays(from: entry.date, limit: 5)
        let rangeLow = days.map(\.low).min() ?? 0
        let rangeHigh = days.map(\.high).max() ?? 1
        VStack(alignment: .leading, spacing: 8) {
            MediumConditionsView(entry: entry, snapshot: snapshot, location: location, current: current)
            if let nextHour = snapshot.nextHour, entry.nextHour.isPrecipitationExpected {
                MinutePrecipitationChart(forecast: nextHour, now: entry.date, showsGuides: false, showsAxis: false)
                    .frame(height: 34)
            }
            Divider().overlay(.white.opacity(0.3))
            VStack(spacing: 5) {
                ForEach(days) { day in
                    HStack(spacing: 8) {
                        Text(formatter.dayLabel(day.date, timeZone: snapshot.timeZone, now: entry.date))
                            .font(.caption.weight(.semibold))
                            .frame(width: 64, alignment: .leading)
                        ConditionIcon(day.condition)
                            .font(.caption)
                            .frame(width: 20)
                        Text(chance(day, formatter))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Palette.rain)
                            .frame(width: 30, alignment: .leading)
                        Text(formatter.temperature(day.low))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 30, alignment: .trailing)
                        TemperatureRangeBar(low: day.low, high: day.high, rangeLow: rangeLow, rangeHigh: rangeHigh)
                        Text(formatter.temperature(day.high))
                            .font(.caption.weight(.semibold))
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }

    private func chance(_ day: DailyForecast, _ formatter: WeatherFormatter) -> String {
        guard let chance = day.precipitationChance, chance >= 0.15 else { return "" }
        return formatter.chance(chance)
    }
}

// MARK: Lock Screen

private struct CircularConditionsView: View {
    let entry: WeatherEntry
    let current: CurrentConditions

    var body: some View {
        let formatter = entry.formatter
        if let today = entry.today, today.high > today.low {
            Gauge(value: min(max(current.temperature, today.low), today.high), in: today.low...today.high) {
                Image(systemName: current.condition.symbolName(isDaylight: current.isDaylight))
            } currentValueLabel: {
                Text(formatter.temperature(current.temperature))
            } minimumValueLabel: {
                Text(formatter.temperature(today.low).replacingOccurrences(of: "°", with: ""))
            } maximumValueLabel: {
                Text(formatter.temperature(today.high).replacingOccurrences(of: "°", with: ""))
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: current.condition.symbolName(isDaylight: current.isDaylight))
                        .font(.caption)
                    Text(formatter.temperature(current.temperature))
                        .font(.title3.weight(.semibold))
                }
            }
        }
    }
}

private struct RectangularConditionsView: View {
    let entry: WeatherEntry
    let location: WeatherLocation
    let current: CurrentConditions

    var body: some View {
        let formatter = entry.formatter
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: current.condition.symbolName(isDaylight: current.isDaylight))
                WidgetLocationName(location: location)
            }
            .font(.headline)
            .widgetAccentable()
            Text("\(formatter.temperature(current.temperature)) · Feels \(formatter.temperature(current.apparentTemperature))")
                .font(.body.weight(.semibold))
            if entry.nextHour.isPrecipitationExpected {
                Text(entry.nextHour.shortText)
                    .font(.caption)
            } else if let today = entry.today {
                Text("H:\(formatter.temperature(today.high)) L:\(formatter.temperature(today.low)) · \(current.condition.description)")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
