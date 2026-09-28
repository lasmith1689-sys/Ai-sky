import AiSkyKit
import Charts
import SwiftUI

/// Everything about one day: hourly chart, summary and statistics.
struct DayDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let snapshot: WeatherSnapshot
    let day: DailyForecast

    var body: some View {
        let formatter = model.formatter
        let timeZone = snapshot.timeZone
        let hours = hoursOfDay
        NavigationStack {
            ZStack {
                SkyBackground(condition: day.condition, isDaylight: true).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            ConditionIcon(day.condition)
                                .font(.system(size: 44))
                            VStack(alignment: .leading) {
                                Text(day.condition.description)
                                    .font(.title2.weight(.semibold))
                                Text("High \(formatter.temperature(day.high)) · Low \(formatter.temperature(day.low))")
                                    .font(.headline)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                        if !hours.isEmpty {
                            Text(ForecastNarrator.daySummary(hours: hours, now: hours[0].date, timeZone: timeZone, formatter: formatter))
                                .font(.callout)

                            WeatherCard(title: "Temperature", systemImage: "thermometer.medium") {
                                HourlyMetricChart(hours: hours, metric: .temperature, formatter: formatter, timeZone: timeZone)
                                    .frame(height: 150)
                            }
                            WeatherCard(title: "Chance of Precipitation", systemImage: "drop.fill") {
                                HourlyMetricChart(hours: hours, metric: .precipitation, formatter: formatter, timeZone: timeZone)
                                    .frame(height: 120)
                            }
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            stats(formatter: formatter, timeZone: timeZone)
                        }
                    }
                    .padding(16)
                }
            }
            .foregroundStyle(.white)
            .navigationTitle(formatter.fullDay(day.date, timeZone: timeZone))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .presentationDetents([.large])
    }

    private var hoursOfDay: [HourlyForecast] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot.timeZone
        return snapshot.hourly.filter { calendar.isDate($0.date, inSameDayAs: day.date) }
    }

    @ViewBuilder
    private func stats(formatter: WeatherFormatter, timeZone: TimeZone) -> some View {
        if let high = day.apparentHigh, let low = day.apparentLow {
            DetailTile(title: "Feels Like", systemImage: "thermometer.sun.fill",
                       value: "\(formatter.temperature(high)) / \(formatter.temperature(low))",
                       detail: "Real-feel high and low.")
        }
        DetailTile(title: "Precipitation", systemImage: "cloud.rain.fill",
                   value: formatter.precipitation(day.precipitationAmount ?? 0),
                   detail: precipitationDetail(formatter: formatter))
        if let wind = day.windSpeedMax {
            DetailTile(title: "Wind", systemImage: "wind",
                       value: formatter.windSpeed(wind),
                       detail: windDetail(formatter: formatter))
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

    private func precipitationDetail(formatter: WeatherFormatter) -> String {
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

    private func windDetail(formatter: WeatherFormatter) -> String? {
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
