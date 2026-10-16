import Foundation

/// Deterministic sample data for SwiftUI previews, widget placeholders and tests.
public enum SampleData {
    public static let location = WeatherLocation(
        id: "sample-chicago",
        name: "Chicago",
        subtitle: "Illinois, United States",
        latitude: 41.8781,
        longitude: -87.6298,
        timeZoneIdentifier: "America/Chicago",
        countryCode: "US"
    )

    public static let savedLocations: [SavedLocation] = [
        SavedLocation(placeName: "Chicago", subtitle: "Illinois, United States", latitude: 41.8781, longitude: -87.6298, timeZoneIdentifier: "America/Chicago", countryCode: "US"),
        SavedLocation(placeName: "New York", customName: "Work", subtitle: "New York, United States", latitude: 40.7128, longitude: -74.0060, timeZoneIdentifier: "America/New_York", countryCode: "US"),
        SavedLocation(placeName: "Denver", subtitle: "Colorado, United States", latitude: 39.7392, longitude: -104.9903, timeZoneIdentifier: "America/Denver", countryCode: "US"),
        SavedLocation(placeName: "London", subtitle: "England, United Kingdom", latitude: 51.5072, longitude: -0.1276, timeZoneIdentifier: "Europe/London", countryCode: "GB"),
    ]

    /// A rainy-afternoon snapshot: light rain starting in ~12 minutes.
    public static func snapshot(now: Date = Date(), location: WeatherLocation = SampleData.location) -> WeatherSnapshot {
        let timeZone = TimeZone(identifier: location.timeZoneIdentifier ?? "America/Chicago") ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let today = calendar.startOfDay(for: now)

        // Next hour, minute by minute.
        var minutes: [MinutePrecipitation] = []
        for minute in 0..<61 {
            let date = now.addingTimeInterval(Double(minute) * 60)
            let intensity: Double
            switch minute {
            case ..<12: intensity = 0
            case ..<20: intensity = Double(minute - 11) * 0.12
            case ..<38: intensity = 1.1 + sin(Double(minute) / 3) * 0.4
            case ..<46: intensity = Double(46 - minute) * 0.1
            default: intensity = 0
            }
            minutes.append(MinutePrecipitation(date: date, intensity: max(0, intensity), chance: intensity > 0 ? 0.8 : 0.1, kind: intensity > 0 ? .rain : .none))
        }

        // Hourly: 24 past hours + 72 ahead.
        var hours: [HourlyForecast] = []
        for offset in -24..<72 {
            let date = hourStart.addingTimeInterval(Double(offset) * 3600)
            let hourOfDay = Double(calendar.component(.hour, from: date))
            let temperature = 19 + 6 * sin((hourOfDay - 9) / 24 * 2 * .pi)
            let rainy = (0...3).contains(offset) || (26...29).contains(offset)
            let isDay = (7...19).contains(Int(hourOfDay))
            hours.append(HourlyForecast(
                date: date,
                condition: rainy ? .lightRain : (offset % 7 == 0 ? .mostlyCloudy : .partlyCloudy),
                isDaylight: isDay,
                temperature: temperature,
                apparentTemperature: temperature + 1.5,
                humidity: rainy ? 0.88 : 0.62,
                dewPoint: 13,
                precipitationChance: rainy ? 0.7 : 0.1,
                precipitationAmount: rainy ? 0.9 : 0,
                snowfallAmount: 0,
                precipitationKind: rainy ? .rain : .none,
                windSpeed: 14 + Double(offset % 5),
                windGust: 28,
                windDirection: 225,
                uvIndex: isDay ? max(0, 6 * sin((hourOfDay - 6) / 14 * .pi)) : 0,
                cloudCover: rainy ? 0.95 : 0.45,
                visibility: rainy ? 8 : 16,
                pressure: 1012 - Double(offset) * 0.1
            ))
        }

        // Daily: 10 days.
        let conditions: [SkyCondition] = [.lightRain, .partlyCloudy, .clear, .mostlyCloudy, .thunderstorms, .rain, .partlyCloudy, .clear, .mostlyClear, .cloudy]
        var days: [DailyForecast] = []
        for offset in 0..<10 {
            let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            let condition = conditions[offset]
            let high = 24 + Double((offset * 3) % 7) - 2
            days.append(DailyForecast(
                date: date,
                condition: condition,
                high: high,
                low: high - 9,
                apparentHigh: high + 1,
                apparentLow: high - 10,
                precipitationChance: condition.isPrecipitation ? 0.7 : 0.1,
                precipitationAmount: condition.isPrecipitation ? 6.5 : 0,
                snowfallAmount: 0,
                precipitationHours: condition.isPrecipitation ? 4 : 0,
                precipitationKind: condition.isPrecipitation ? .rain : .none,
                sunrise: date.addingTimeInterval(6.7 * 3600),
                sunset: date.addingTimeInterval(18.6 * 3600),
                uvIndexMax: 6,
                windSpeedMax: 22,
                windGustMax: 38,
                windDirectionDominant: 220
            ))
        }

        // History: 31 days of daily totals + 7 days hourly.
        var historyDaily: [PrecipitationSample] = []
        for offset in 1...31 {
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let amount = offset % 6 == 0 ? 12.0 : (offset % 4 == 0 ? 3.2 : 0)
            historyDaily.append(PrecipitationSample(date: date, amount: amount, snowfall: 0))
        }
        var historyHourly: [PrecipitationSample] = []
        for offset in 1...168 {
            let date = hourStart.addingTimeInterval(-Double(offset) * 3600)
            let amount = (30...34).contains(offset) ? 1.4 : (offset == 100 ? 4.0 : 0)
            historyHourly.append(PrecipitationSample(date: date, amount: amount, snowfall: 0))
        }

        let airQuality = AirQuality(
            date: now,
            usAQI: 42,
            europeanAQI: 24,
            pollutants: [
                PollutantReading(pollutant: .pm2_5, concentration: 9.8, usAQI: 42, europeanAQI: 20),
                PollutantReading(pollutant: .pm10, concentration: 15.1, usAQI: 14, europeanAQI: 11),
                PollutantReading(pollutant: .ozone, concentration: 61, usAQI: 30, europeanAQI: 24),
                PollutantReading(pollutant: .nitrogenDioxide, concentration: 18.2, usAQI: 16, europeanAQI: 9),
                PollutantReading(pollutant: .sulphurDioxide, concentration: 2.1, usAQI: 1, europeanAQI: 1),
                PollutantReading(pollutant: .carbonMonoxide, concentration: 212, usAQI: 2, europeanAQI: nil),
            ],
            pollen: [PollenReading(type: .grass, concentration: 12), PollenReading(type: .ragweed, concentration: 34)],
            dust: 0.5,
            hourly: (0..<96).map { offset in
                AQIForecastPoint(date: hourStart.addingTimeInterval(Double(offset) * 3600),
                                 usAQI: 35 + 20 * sin(Double(offset) / 8), europeanAQI: 20 + 10 * sin(Double(offset) / 8))
            }
        )

        return WeatherSnapshot(
            location: location,
            fetchedAt: now,
            source: .openMeteo,
            timeZoneIdentifier: timeZone.identifier,
            current: CurrentConditions(
                date: now,
                condition: .mostlyCloudy,
                isDaylight: true,
                temperature: 22.4,
                apparentTemperature: 24.1,
                humidity: 0.71,
                dewPoint: 16.8,
                pressure: 1011.6,
                pressureTrend: .falling,
                windSpeed: 17,
                windGust: 31,
                windDirection: 215,
                uvIndex: 4,
                visibility: 14,
                cloudCover: 0.78,
                precipitationIntensity: 0
            ),
            nextHour: NextHourForecast(minutes: minutes, resolution: 60),
            hourly: hours,
            daily: days,
            precipitationHistory: PrecipitationHistory(hourly: historyHourly, daily: historyDaily),
            airQuality: airQuality,
            alerts: [],
            notes: []
        )
    }

    public static let sampleAlert = WeatherAlertInfo(
        id: "sample-alert",
        title: "Severe Thunderstorm Watch",
        headline: "Severe Thunderstorm Watch issued until 9:00 PM CDT",
        details: "Conditions are favorable for severe thunderstorms capable of damaging winds and large hail.",
        instruction: "Be prepared to move to a place of safety if threatening weather approaches.",
        severity: .severe,
        source: "National Weather Service",
        region: "Cook County, IL"
    )
}
