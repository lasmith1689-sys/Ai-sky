import AiSkyKit
import SwiftUI

/// 10-day forecast with temperature range bars.
struct DailyCard: View {
    @Environment(AppModel.self) private var model
    let snapshot: WeatherSnapshot
    let now: Date
    let onSelect: (DailyForecast) -> Void

    var body: some View {
        let formatter = model.formatter
        let days = snapshot.upcomingDays(from: now, limit: 10)
        let rangeLow = days.map(\.low).min() ?? 0
        let rangeHigh = days.map(\.high).max() ?? 1
        WeatherCard(title: "\(days.count)-Day Forecast", systemImage: "calendar") {
            Text(ForecastNarrator.weekSummary(days: days, now: now, timeZone: snapshot.timeZone, formatter: formatter))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(days) { day in
                    Divider().overlay(.white.opacity(0.15))
                    Button {
                        onSelect(day)
                    } label: {
                        DayRow(
                            day: day,
                            label: formatter.dayLabel(day.date, timeZone: snapshot.timeZone, now: now),
                            formatter: formatter,
                            rangeLow: rangeLow,
                            rangeHigh: rangeHigh,
                            current: isToday(day) ? snapshot.current.temperature : nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func isToday(_ day: DailyForecast) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot.timeZone
        return calendar.isDate(day.date, inSameDayAs: now)
    }
}

private struct DayRow: View {
    let day: DailyForecast
    let label: String
    let formatter: WeatherFormatter
    let rangeLow: Double
    let rangeHigh: Double
    let current: Double?

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.body.weight(.medium))
                .frame(width: 84, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            VStack(spacing: 0) {
                ConditionIcon(day.condition)
                    .font(.title3)
                if let chance = day.precipitationChance, chance >= 0.15 {
                    Text(formatter.chance(chance))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Palette.rain)
                }
            }
            .frame(width: 36)
            Text(formatter.temperature(day.low))
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 38, alignment: .trailing)
            TemperatureRangeBar(low: day.low, high: day.high, rangeLow: rangeLow, rangeHigh: rangeHigh, current: current)
            Text(formatter.temperature(day.high))
                .frame(width: 38, alignment: .trailing)
        }
        .font(.body.weight(.medium))
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(day.condition.description), high \(formatter.temperature(day.high)), low \(formatter.temperature(day.low))")
    }
}
