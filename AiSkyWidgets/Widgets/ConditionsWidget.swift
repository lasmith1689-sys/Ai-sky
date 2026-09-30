import AiSkyKit
import SwiftUI
import WidgetKit

/// Current conditions for any saved place, on the Home Screen and Lock Screen.
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
        let t = entry.tokens
        VStack(alignment: .leading, spacing: 2) {
            WidgetLocationName(location: location)
                .font(t.look == .liquid ? .subheadline.weight(.semibold) : t.font(.textStrong, 14))
                .widgetAccentable()
            Text(formatter.temperature(current.temperature))
                .font(t.look == .liquid ? .system(size: 44, weight: .light) : t.font(.display, 46))
                .minimumScaleFactor(0.6)
                .widgetAccentable()
            Spacer(minLength: 0)
            WidgetConditionIcon(condition: current.condition, isDaylight: current.isDaylight, tokens: t)
                .font(.title3)
            Text(current.condition.description)
                .font(t.look == .liquid ? .caption.weight(.semibold) : t.font(.textStrong, 12))
                .lineLimit(1)
            if entry.nextHour.isPrecipitationExpected {
                Text(entry.nextHour.shortText)
                    .font(t.look == .liquid ? .caption2.weight(.semibold) : t.font(.textStrong, 11))
                    .foregroundStyle(t.rainText)
                    .lineLimit(1)
            } else {
                Text("Feels \(formatter.temperature(current.apparentTemperature))")
                    .font(t.look == .liquid ? .caption2.weight(.medium) : t.font(.text, 11))
                    .foregroundStyle(t.ink2)
            }
            if let today = entry.today {
                Text("H:\(formatter.temperature(today.high)) L:\(formatter.temperature(today.low))")
                    .font(t.look == .liquid ? .caption2.weight(.medium) : t.font(.text, 11))
                    .foregroundStyle(t.ink2)
            }
        }
        .foregroundStyle(t.ink)
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
        let t = entry.tokens
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetLocationName(location: location)
                        .font(t.look == .liquid ? .subheadline.weight(.semibold) : t.font(.textStrong, 14))
                        .widgetAccentable()
                    Text(formatter.temperature(current.temperature))
                        .font(t.look == .liquid ? .system(size: 40, weight: .light) : t.font(.display, 42))
                        .widgetAccentable()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    WidgetConditionIcon(condition: current.condition, isDaylight: current.isDaylight, tokens: t)
                        .font(.title3)
                    Text(current.condition.description)
                        .font(t.look == .liquid ? .caption.weight(.semibold) : t.font(.textStrong, 12))
                        .lineLimit(1)
                    Group {
                        Text("Feels \(formatter.temperature(current.apparentTemperature))")
                        if let today = entry.today {
                            Text("H:\(formatter.temperature(today.high)) L:\(formatter.temperature(today.low))")
                        }
                    }
                    .font(t.look == .liquid ? .caption2 : t.font(.text, 11))
                    .foregroundStyle(t.ink2)
                }
            }
            if entry.nextHour.isPrecipitationExpected {
                Text(entry.nextHour.text)
                    .font(t.look == .liquid ? .caption2.weight(.semibold) : t.font(.textStrong, 11))
                    .foregroundStyle(t.rainText)
                    .lineLimit(1)
            }
            HStack(spacing: 0) {
                let hours = snapshot.upcomingHours(from: entry.date, limit: 6)
                ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                    WidgetHourColumn(hour: hour, formatter: formatter, timeZone: snapshot.timeZone, isFirst: index == 0, tokens: t)
                }
            }
        }
        .foregroundStyle(t.ink)
    }
}

private struct LargeConditionsView: View {
    let entry: WeatherEntry
    let snapshot: WeatherSnapshot
    let location: WeatherLocation
    let current: CurrentConditions

    var body: some View {
        let formatter = entry.formatter
        let t = entry.tokens
        let days = snapshot.upcomingDays(from: entry.date, limit: 5)
        let rangeLow = days.map(\.low).min() ?? 0
        let rangeHigh = days.map(\.high).max() ?? 1
        VStack(alignment: .leading, spacing: 8) {
            MediumConditionsView(entry: entry, snapshot: snapshot, location: location, current: current)
            if let nextHour = snapshot.nextHour, entry.nextHour.isPrecipitationExpected {
                MinuteBars(forecast: nextHour, now: entry.date, wetColor: t.rain, dryColor: t.track)
                    .frame(height: 30)
            }
            Rectangle().fill(t.line).frame(height: 1)
            VStack(spacing: 5) {
                ForEach(days) { day in
                    HStack(spacing: 8) {
                        Text(formatter.dayLabel(day.date, timeZone: snapshot.timeZone, now: entry.date))
                            .font(t.look == .liquid ? .caption.weight(.semibold) : t.font(.textStrong, 12))
                            .frame(width: 64, alignment: .leading)
                        WidgetConditionIcon(condition: day.condition, tokens: t)
                            .font(.caption)
                            .frame(width: 20)
                        Text(chance(day, formatter))
                            .font(t.look == .liquid ? .caption2.weight(.bold) : t.font(.textStrong, 10))
                            .foregroundStyle(t.rainText)
                            .frame(width: 30, alignment: .leading)
                        Text(formatter.temperature(day.low))
                            .font(t.look == .liquid ? .caption : t.font(.number, 12))
                            .foregroundStyle(t.ink2)
                            .frame(width: 30, alignment: .trailing)
                        if t.usesTemperatureColors {
                            TemperatureRangeBar(low: day.low, high: day.high, rangeLow: rangeLow, rangeHigh: rangeHigh)
                        } else {
                            LookRangeBar(low: day.low, high: day.high, rangeLow: rangeLow, rangeHigh: rangeHigh,
                                         height: 4, fill: t.look == .chroma ? ChromaPalette.mustard : t.ink, track: t.track)
                                .widgetAccentable()
                        }
                        Text(formatter.temperature(day.high))
                            .font(t.look == .liquid ? .caption.weight(.semibold) : t.font(.number, 12))
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(t.ink)
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
