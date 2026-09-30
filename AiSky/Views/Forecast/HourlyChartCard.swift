import AiSkyKit
import Charts
import SwiftUI

/// Any hourly metric for the next 24 hours as a chart, with a selector. Each look draws its own
/// hourly strip above; this card is shared.
struct HourlyChartCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lookTokens) private var t
    let snapshot: WeatherSnapshot
    let now: Date

    @State private var metric: HourlyMetric = .temperature

    var body: some View {
        let formatter = model.formatter
        let hours = snapshot.upcomingHours(from: now, limit: 24)
        WeatherCard(title: "Next 24 Hours", systemImage: "chart.xyaxis.line", tone: .navy) {
            Text(ForecastNarrator.daySummary(hours: snapshot.hourly, now: now, timeZone: snapshot.timeZone, formatter: formatter))
                .font(t.look == .liquid ? .subheadline : t.font(.text, t.bodySize))
                .foregroundStyle(t.toned(.navy).ink2)
                .fixedSize(horizontal: false, vertical: true)
            HourlyChartBody(hours: hours, formatter: formatter, timeZone: snapshot.timeZone, metric: $metric)
        }
    }
}

/// Metric selector and chart, inside a card that has already set the tokens.
private struct HourlyChartBody: View {
    @Environment(\.lookTokens) private var t
    let hours: [HourlyForecast]
    let formatter: WeatherFormatter
    let timeZone: TimeZone
    @Binding var metric: HourlyMetric

    var body: some View {
        LookChips(options: HourlyMetric.allCases, selection: $metric, title: \.title)
        HourlyMetricChart(hours: hours, metric: metric, formatter: formatter, timeZone: timeZone)
            .frame(height: 150)
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
    @Environment(\.lookTokens) private var t
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
                AxisGridLine().foregroundStyle(t.grid)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(LookClock.hour(date, timeZone: timeZone, tokens: t, formatter: formatter))
                            .font(axisFont)
                            .foregroundStyle(t.ink2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(t.grid)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(axisLabel(number))
                            .font(axisFont)
                            .foregroundStyle(t.ink2)
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
            .foregroundStyle(barColor(hour).opacity(0.85))
            .cornerRadius(2)
        } else if metric == .amount {
            BarMark(
                x: .value("Time", hour.date, unit: .hour),
                y: .value("Amount", formatter.precipitationValue(hour.precipitationAmount ?? 0))
            )
            .foregroundStyle(barColor(hour))
            .cornerRadius(2)
        } else if metric == .uv {
            BarMark(
                x: .value("Time", hour.date, unit: .hour),
                y: .value("UV", hour.uvIndex ?? 0)
            )
            .foregroundStyle(t.usesTemperatureColors ? Palette.uv(UVCategory(index: hour.uvIndex ?? 0)) : t.chartLine.opacity(0.8))
            .cornerRadius(2)
        } else {
            LineMark(
                x: .value("Time", hour.date),
                y: .value(metric.title, value(for: hour))
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(lineGradient)
            .lineStyle(StrokeStyle(lineWidth: t.surfaceStyle == .hairline ? 1.5 : 2.5))
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

    private var axisFont: Font {
        t.look == .liquid ? .caption2 : t.font(.label, 10, relativeTo: .caption2)
    }

    /// Precipitation bars: the look's rain color, or the precipitation type's color on the sky.
    private func barColor(_ hour: HourlyForecast) -> Color {
        t.usesTemperatureColors ? Palette.precipitation(hour.precipitationKind) : t.rain
    }

    /// Top-to-bottom colors for the line: warm at the top of the chart, cool at the bottom (Liquid),
    /// or the look's single line color.
    private var lineColors: [Color] {
        guard t.usesTemperatureColors else {
            switch metric {
            case .precipitation, .amount: return [t.rain, t.rain]
            default: return [t.chartLine, t.chartLine]
            }
        }
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
        let top = t.usesTemperatureColors ? lineColors[0].opacity(0.35) : t.chartArea
        return LinearGradient(colors: [top, top.opacity(0)], startPoint: .top, endPoint: .bottom)
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
