import AiSkyKit
import Charts
import SwiftUI

/// Everything about one forecast day: hourly chart, summary and statistics.
struct DayDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lookTokens) private var t
    let snapshot: WeatherSnapshot
    let day: DailyForecast

    var body: some View {
        let timeZone = snapshot.timeZone
        NavigationStack {
            ZStack {
                LookPageBackground(condition: day.condition, isDaylight: true).ignoresSafeArea()
                ScrollView {
                    DayDetailContent(day: day, hours: hoursOfDay, timeZone: timeZone)
                        .padding(.horizontal, t.gutter)
                        .padding(.vertical, 16)
                }
            }
            .foregroundStyle(t.ink)
            .lookNavigationTitle(model.formatter.fullDay(day.date, timeZone: timeZone))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var hoursOfDay: [HourlyForecast] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot.timeZone
        return snapshot.hourly.filter { calendar.isDate($0.date, inSameDayAs: day.date) }
    }
}

/// A day's summary, hourly charts and statistics; shared by forecast days and the Time Machine.
struct DayDetailContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lookTokens) private var t
    let day: DailyForecast?
    let hours: [HourlyForecast]
    let timeZone: TimeZone
    /// Past days chart what fell rather than the chance of precipitation.
    var isPast = false

    var body: some View {
        let formatter = model.formatter
        VStack(alignment: .leading, spacing: t.sectionSpacing) {
            if let day {
                HStack(spacing: 12) {
                    if t.look == .liquid {
                        ConditionIcon(day.condition)
                            .font(.system(size: 44))
                    } else {
                        OutlineConditionIcon(day.condition)
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(t.look == .chroma ? ChromaPalette.cobalt : t.ink2)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.look == .liquid ? day.condition.description : sentenceCase(day.condition.description))
                            .font(t.look == .liquid ? .title2.weight(.semibold) : t.font(.headline, 24))
                        Text("High \(formatter.temperature(day.high)) · Low \(formatter.temperature(day.low))")
                            .font(t.look == .liquid ? .headline : t.font(.textMedium, 16))
                            .foregroundStyle(t.ink2)
                    }
                }
            }
            if !hours.isEmpty {
                Text(ForecastNarrator.daySummary(hours: hours, now: hours[0].date, timeZone: timeZone, formatter: formatter))
                    .font(t.look == .liquid ? .callout : t.font(t.look == .editorial ? .number : .text, t.bodySize + 1))
                    .fixedSize(horizontal: false, vertical: true)

                WeatherCard(title: "Temperature", systemImage: "thermometer.medium", tone: .navy) {
                    HourlyMetricChart(hours: hours, metric: .temperature, formatter: formatter, timeZone: timeZone)
                        .frame(height: 150)
                }
                if isPast {
                    WeatherCard(title: "Precipitation", systemImage: "drop.fill", accessory: totalText(formatter: formatter), tone: .cobalt) {
                        HourlyMetricChart(hours: hours, metric: .amount, formatter: formatter, timeZone: timeZone)
                            .frame(height: 120)
                    }
                } else {
                    WeatherCard(title: "Chance of Precipitation", systemImage: "drop.fill", tone: .cobalt) {
                        HourlyMetricChart(hours: hours, metric: .precipitation, formatter: formatter, timeZone: timeZone)
                            .frame(height: 120)
                    }
                }
                WeatherCard(title: "Wind", systemImage: "wind") {
                    HourlyMetricChart(hours: hours, metric: .wind, formatter: formatter, timeZone: timeZone)
                        .frame(height: 110)
                }
            }
            if let day {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    stats(day: day, formatter: formatter)
                }
            }
        }
    }

    private func totalText(formatter: WeatherFormatter) -> String? {
        guard let total = day?.precipitationAmount ?? optionalSum(hours.compactMap(\.precipitationAmount)) else { return nil }
        return "\(formatter.precipitation(total)) total"
    }

    private func optionalSum(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +)
    }

    @ViewBuilder
    private func stats(day: DailyForecast, formatter: WeatherFormatter) -> some View {
        if let high = day.apparentHigh, let low = day.apparentLow {
            DetailTile(title: "Feels Like", systemImage: "thermometer.sun.fill",
                       value: "\(formatter.temperature(high)) / \(formatter.temperature(low))",
                       detail: "Real-feel high and low.")
        }
        DetailTile(title: "Precipitation", systemImage: "cloud.rain.fill",
                   value: formatter.precipitation(day.precipitationAmount ?? 0),
                   detail: precipitationDetail(day: day, formatter: formatter))
        if let wind = day.windSpeedMax {
            DetailTile(title: "Wind", systemImage: "wind",
                       value: formatter.windSpeed(wind),
                       detail: windDetail(day: day, formatter: formatter))
        }
        if let humidity = averageHumidity {
            DetailTile(title: "Humidity", systemImage: "humidity.fill",
                       value: formatter.percent(humidity),
                       detail: "Average for the day.")
        }
        if let uv = day.uvIndexMax {
            DetailTile(title: "UV Index", systemImage: "sun.max.fill",
                       value: "\(Int(uv.rounded()))",
                       detail: "\(UVCategory(index: uv).name) at its peak.")
        }
        if day.sunrise != nil || day.sunset != nil {
            DetailTile(title: "Sun", systemImage: "sunrise.fill",
                       value: day.sunrise.map { formatter.time($0, timeZone: timeZone) } ?? "--",
                       detail: day.sunset.map { "Sunset \(formatter.time($0, timeZone: timeZone))" })
        }
        let moon = day.moon
        DetailTile(title: "Moon", systemImage: moon.phase.symbolName,
                   value: moon.phase.name,
                   detail: "\(Int((moon.illumination * 100).rounded()))% illuminated")
    }

    private var averageHumidity: Double? {
        let values = hours.compactMap(\.humidity)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private func precipitationDetail(day: DailyForecast, formatter: WeatherFormatter) -> String {
        var parts: [String] = []
        if let chance = day.precipitationChance {
            parts.append("\(formatter.percent(chance)) chance")
        }
        if let snow = day.snowfallAmount, snow >= 0.1 {
            parts.append("\(formatter.snowfall(snow)) of snow")
        }
        if let hours = day.precipitationHours, hours > 0 {
            parts.append("\(Int(hours.rounded())) hr of precipitation")
        }
        return parts.joined(separator: " · ")
    }

    private func windDetail(day: DailyForecast, formatter: WeatherFormatter) -> String? {
        var parts: [String] = []
        if let gust = day.windGustMax {
            parts.append("Gusts \(formatter.windSpeed(gust))")
        }
        if let direction = day.windDirectionDominant {
            parts.append("from the \(WeatherFormatter.compassDirectionName(direction))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
