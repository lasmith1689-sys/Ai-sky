import AiSkyKit
import Charts
import SwiftUI

/// Next 48 hours: a Dark Sky style condition strip plus a chart for any metric.
struct HourlyCard: View {
    @Environment(AppModel.self) private var model
    let snapshot: WeatherSnapshot
    let now: Date

    @State private var metric: HourlyMetric = .temperature

    var body: some View {
        let formatter = model.formatter
        let hours = snapshot.upcomingHours(from: now, limit: 48)
        WeatherCard(title: "Next 48 Hours", systemImage: "clock.arrow.circlepath") {
            Text(ForecastNarrator.daySummary(hours: snapshot.hourly, now: now, timeZone: snapshot.timeZone, formatter: formatter))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(.white.opacity(0.2))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(items(hours: hours)) { item in
                        HourColumn(item: item, snapshot: snapshot, formatter: formatter, now: now)
                    }
                }
            }

            Divider().overlay(.white.opacity(0.2))

            MetricChips(selection: $metric)

            HourlyMetricChart(hours: Array(hours.prefix(24)), metric: metric, formatter: formatter, timeZone: snapshot.timeZone)
                .frame(height: 150)
        }
    }

    /// Hours with sunrise / sunset markers slotted in, like Apple Weather.
    private func items(hours: [HourlyForecast]) -> [HourItem] {
        guard let first = hours.first?.date, let last = hours.last?.date else { return [] }
        var items = hours.map { HourItem.hour($0) }
        let sunEvents: [HourItem] = snapshot.daily.flatMap { day -> [HourItem] in
            var events: [HourItem] = []
            if let sunrise = day.sunrise { events.append(.sun(sunrise, rising: true)) }
            if let sunset = day.sunset { events.append(.sun(sunset, rising: false)) }
            return events
        }
        .filter { $0.date > max(first, now) && $0.date < last }
        items += sunEvents
        return items.sorted { $0.date < $1.date }
    }
}

enum HourItem: Identifiable {
    case hour(HourlyForecast)
    case sun(Date, rising: Bool)

    var id: String {
        switch self {
        case .hour(let hour): return "h\(hour.date.timeIntervalSince1970)"
        case .sun(let date, let rising): return "\(rising ? "r" : "s")\(date.timeIntervalSince1970)"
        }
    }

    var date: Date {
        switch self {
        case .hour(let hour): return hour.date
        case .sun(let date, _): return date
        }
    }
}

private struct HourColumn: View {
    let item: HourItem
    let snapshot: WeatherSnapshot
    let formatter: WeatherFormatter
    let now: Date

    var body: some View {
        VStack(spacing: 7) {
            switch item {
            case .hour(let hour):
                Rectangle()
                    .fill(Palette.conditionBar(hour.condition.family))
                    .frame(height: 5)
                Text(isNow(hour) ? "Now" : formatter.hour(hour.date, timeZone: snapshot.timeZone))
                    .font(.caption.weight(isNow(hour) ? .bold : .medium))
                ConditionIcon(hour.condition, isDaylight: hour.isDaylight)
                    .font(.title3)
                    .frame(height: 28)
                Text(chanceText(hour))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.rain)
                Text(formatter.temperature(hour.temperature))
                    .font(.callout.weight(.semibold))
            case .sun(let date, let rising):
                Rectangle()
                    .fill(Color.orange.opacity(0.6))
                    .frame(height: 5)
                Text(formatter.time(date, timeZone: snapshot.timeZone))
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: rising ? "sunrise.fill" : "sunset.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.title3)
                    .frame(height: 28)
                Text(" ")
                    .font(.caption2)
                Text(rising ? "Sunrise" : "Sunset")
                    .font(.caption.weight(.semibold))
            }
        }
        .frame(width: 58)
    }

    private func isNow(_ hour: HourlyForecast) -> Bool {
        hour.date <= now && now.timeIntervalSince(hour.date) < 3600
    }

    private func chanceText(_ hour: HourlyForecast) -> String {
        guard let chance = hour.precipitationChance, chance >= 0.15 else { return " " }
        return formatter.chance(chance)
    }
}

/// Horizontally scrolling metric selector (seven options don't fit a segmented control).
private struct MetricChips: View {
    @Binding var selection: HourlyMetric

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(HourlyMetric.allCases) { option in
                    let selected = option == selection
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selection = option }
                    } label: {
                        Text(option.title)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selected ? Color.white.opacity(0.9) : Color.white.opacity(0.12), in: Capsule())
                            .foregroundStyle(selected ? Color.black : Color.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}

enum HourlyMetric: String, CaseIterable, Identifiable {
    case temperature
    case feelsLike
    case precipitation
    case amount
    case wind
    case uv
    case humidity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .temperature: return "Temp"
        case .feelsLike: return "Feels"
        case .precipitation: return "Chance"
        case .amount: return "Amount"
        case .wind: return "Wind"
        case .uv: return "UV"
        case .humidity: return "Humidity"
        }
    }
}

/// Line / bar chart of one metric for the next 24 hours.
struct HourlyMetricChart: View {
    let hours: [HourlyForecast]
    let metric: HourlyMetric
    let formatter: WeatherFormatter
    let timeZone: TimeZone

    var body: some View {
        Chart {
            ForEach(hours) { hour in
                mark(for: hour)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.15))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(formatter.hour(date, timeZone: timeZone))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.1))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(axisLabel(number))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
        .chartYScale(domain: yDomain)
        .animation(.easeInOut(duration: 0.25), value: metric)
    }

    @ChartContentBuilder
    private func mark(for hour: HourlyForecast) -> some ChartContent {
        if metric == .precipitation {
            BarMark(
                x: .value("Time", hour.date, unit: .hour),
                y: .value("Chance", (hour.precipitationChance ?? 0) * 100)
            )
            .foregroundStyle(Palette.precipitation(hour.precipitationKind).opacity(0.85))
            .cornerRadius(2)
        } else if metric == .amount {
            BarMark(
                x: .value("Time", hour.date, unit: .hour),
                y: .value("Amount", formatter.precipitationValue(hour.precipitationAmount ?? 0))
            )
            .foregroundStyle(Palette.precipitation(hour.precipitationKind))
            .cornerRadius(2)
        } else if metric == .uv {
            BarMark(
                x: .value("Time", hour.date, unit: .hour),
                y: .value("UV", hour.uvIndex ?? 0)
            )
            .foregroundStyle(Palette.uv(UVCategory(index: hour.uvIndex ?? 0)))
            .cornerRadius(2)
        } else {
            LineMark(
                x: .value("Time", hour.date),
                y: .value(metric.title, value(for: hour))
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(lineGradient)
            .lineStyle(StrokeStyle(lineWidth: 2.5))
            AreaMark(
                x: .value("Time", hour.date),
                yStart: .value("Base", yDomain.lowerBound),
                yEnd: .value(metric.title, value(for: hour))
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(areaGradient)
        }
    }

    private func value(for hour: HourlyForecast) -> Double {
        switch metric {
        case .temperature: return formatter.temperatureValue(hour.temperature)
        case .feelsLike: return formatter.temperatureValue(hour.apparentTemperature ?? hour.temperature)
        case .wind: return formatter.windSpeedValue(hour.windSpeed ?? 0)
        case .humidity: return (hour.humidity ?? 0) * 100
        case .precipitation: return (hour.precipitationChance ?? 0) * 100
        case .amount: return formatter.precipitationValue(hour.precipitationAmount ?? 0)
        case .uv: return hour.uvIndex ?? 0
        }
    }

    /// Top-to-bottom colors for the line: warm at the top of the chart, cool at the bottom.
    private var lineColors: [Color] {
        switch metric {
        case .temperature, .feelsLike:
            let celsius = hours.map { metric == .feelsLike ? ($0.apparentTemperature ?? $0.temperature) : $0.temperature }
            let low = celsius.min() ?? 0
            let high = celsius.max() ?? 0
            return [Palette.temperature(high), Palette.temperature((high + low) / 2), Palette.temperature(low)]
        case .wind: return [.teal, .teal]
        case .humidity: return [.cyan, .cyan]
        case .precipitation, .amount: return [Palette.rain, Palette.rain]
        case .uv: return [.yellow, .yellow]
        }
    }

    private var lineGradient: LinearGradient {
        LinearGradient(colors: lineColors, startPoint: .top, endPoint: .bottom)
    }

    private var areaGradient: LinearGradient {
        LinearGradient(colors: [lineColors[0].opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
    }

    private var yDomain: ClosedRange<Double> {
        switch metric {
        case .precipitation, .humidity:
            return 0...100
        case .uv:
            return 0...max(11, hours.compactMap(\.uvIndex).max() ?? 0)
        case .amount:
            // At least 0.1 in / 2.5 mm so light rain doesn't look torrential.
            let floor = formatter.units.precipitation == .inches ? 0.1 : 2.5
            return 0...max(floor, (hours.map { value(for: $0) }.max() ?? 0) * 1.2)
        case .wind:
            return 0...max(10, (hours.map { value(for: $0) }.max() ?? 0) * 1.2)
        case .temperature, .feelsLike:
            let values = hours.map { value(for: $0) }
            let low = (values.min() ?? 0) - 3
            let high = (values.max() ?? 1) + 3
            return low...max(high, low + 1)
        }
    }

    private func axisLabel(_ value: Double) -> String {
        switch metric {
        case .temperature, .feelsLike: return "\(Int(value.rounded()))°"
        case .precipitation, .humidity: return "\(Int(value))%"
        case .amount: return String(format: formatter.units.precipitation == .inches ? "%.2f" : "%.1f", value)
        case .wind: return "\(Int(value))"
        case .uv: return "\(Int(value))"
        }
    }
}
