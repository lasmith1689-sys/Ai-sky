import Foundation

/// Attribution Apple requires wherever Apple Weather data is shown.
public struct WeatherAttributionInfo: Codable, Sendable, Equatable {
    public var serviceName: String
    public var legalPageURL: URL
    public var combinedMarkLightURL: URL
    public var combinedMarkDarkURL: URL

    public init(serviceName: String, legalPageURL: URL, combinedMarkLightURL: URL, combinedMarkDarkURL: URL) {
        self.serviceName = serviceName
        self.legalPageURL = legalPageURL
        self.combinedMarkLightURL = combinedMarkLightURL
        self.combinedMarkDarkURL = combinedMarkDarkURL
    }
}

#if canImport(WeatherKit) && canImport(CoreLocation)
import CoreLocation
import WeatherKit

/// Apple Weather (WeatherKit) — the successor to Dark Sky. Provides true minute-by-minute
/// precipitation for the next hour and worldwide government alerts.
///
/// Requires the WeatherKit capability, which needs a paid Apple Developer Program membership.
@available(iOS 16.0, macOS 13.0, *)
public struct WeatherKitProvider: Sendable {
    public init() {}

    public func forecast(for location: WeatherLocation, now: Date = Date()) async throws -> WeatherSnapshot {
        let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let hourlyStart = now.addingTimeInterval(-24 * 3600)
        let hourlyEnd = now.addingTimeInterval(Double(OpenMeteoClient.forecastDays) * 24 * 3600)
        let (current, minute, hourly, daily, alerts) = try await WeatherService.shared.weather(
            for: clLocation,
            including: .current, .minute, .hourly(startDate: hourlyStart, endDate: hourlyEnd), .daily, .alerts
        )

        let hours = hourly.forecast.map(Self.hour(from:))
        let pressureTrend = Self.pressureTrend(current.pressureTrend)
        let conditions = CurrentConditions(
            date: current.date,
            condition: SkyCondition(weatherKit: current.condition),
            isDaylight: current.isDaylight,
            temperature: current.temperature.converted(to: .celsius).value,
            apparentTemperature: current.apparentTemperature.converted(to: .celsius).value,
            humidity: current.humidity,
            dewPoint: current.dewPoint.converted(to: .celsius).value,
            pressure: current.pressure.converted(to: .hectopascals).value,
            pressureTrend: pressureTrend,
            windSpeed: current.wind.speed.converted(to: .kilometersPerHour).value,
            windGust: current.wind.gust?.converted(to: .kilometersPerHour).value,
            windDirection: current.wind.direction.converted(to: .degrees).value,
            uvIndex: Double(current.uvIndex.value),
            visibility: current.visibility.converted(to: .kilometers).value,
            cloudCover: current.cloudCover,
            precipitationIntensity: Self.millimetersPerHour(current.precipitationIntensity)
        )

        var nextHour: NextHourForecast?
        if let minute, !minute.forecast.isEmpty {
            let samples = minute.forecast.map { item in
                MinutePrecipitation(
                    date: item.date,
                    intensity: Self.millimetersPerHour(item.precipitationIntensity),
                    chance: item.precipitationChance,
                    kind: Self.precipitationKind(item.precipitation)
                )
            }
            let summary = minute.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            nextHour = NextHourForecast(minutes: samples, resolution: 60, providerSummary: summary.isEmpty ? nil : summary)
        }

        let days = daily.forecast.map(Self.day(from:))
        let alertInfos = (alerts ?? []).map { alert in
            WeatherAlertInfo(
                id: alert.detailsURL.absoluteString,
                title: alert.summary,
                severity: Self.severity(alert.severity),
                source: alert.source,
                region: alert.region,
                effective: alert.metadata.date,
                expires: alert.metadata.expirationDate,
                detailsURL: alert.detailsURL
            )
        }

        return WeatherSnapshot(
            location: location,
            fetchedAt: now,
            source: .appleWeather,
            timeZoneIdentifier: location.timeZoneIdentifier ?? TimeZone.current.identifier,
            current: conditions,
            nextHour: nextHour,
            hourly: hours,
            daily: days,
            alerts: alertInfos
        )
    }

    /// Current conditions and today's range only (for the location list).
    public func summary(for location: WeatherLocation, now: Date = Date()) async throws -> LocationWeatherSummary {
        let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let (current, daily) = try await WeatherService.shared.weather(for: clLocation, including: .current, .daily)
        let today = daily.forecast.first
        return LocationWeatherSummary(
            locationID: location.id,
            fetchedAt: now,
            timeZoneIdentifier: location.timeZoneIdentifier ?? TimeZone.current.identifier,
            temperature: current.temperature.converted(to: .celsius).value,
            apparentTemperature: current.apparentTemperature.converted(to: .celsius).value,
            condition: SkyCondition(weatherKit: current.condition),
            isDaylight: current.isDaylight,
            high: today?.highTemperature.converted(to: .celsius).value,
            low: today?.lowTemperature.converted(to: .celsius).value,
            precipitationChance: today?.precipitationChance,
            source: .appleWeather
        )
    }

    /// Only the next-hour minute forecast — used by background rain alerts.
    public func nextHour(for location: WeatherLocation) async throws -> NextHourForecast? {
        let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        guard let minute = try await WeatherService.shared.weather(for: clLocation, including: .minute),
              !minute.forecast.isEmpty else {
            return nil
        }
        let samples = minute.forecast.map { item in
            MinutePrecipitation(
                date: item.date,
                intensity: Self.millimetersPerHour(item.precipitationIntensity),
                chance: item.precipitationChance,
                kind: Self.precipitationKind(item.precipitation)
            )
        }
        return NextHourForecast(minutes: samples, resolution: 60, providerSummary: minute.summary)
    }

    /// Only government alerts — used by background severe-weather notifications.
    public func alerts(for location: WeatherLocation) async throws -> [WeatherAlertInfo] {
        let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let alerts = try await WeatherService.shared.weather(for: clLocation, including: .alerts) ?? []
        return alerts.map { alert in
            WeatherAlertInfo(
                id: alert.detailsURL.absoluteString,
                title: alert.summary,
                severity: Self.severity(alert.severity),
                source: alert.source,
                region: alert.region,
                effective: alert.metadata.date,
                expires: alert.metadata.expirationDate,
                detailsURL: alert.detailsURL
            )
        }
    }

    public static func attribution() async throws -> WeatherAttributionInfo {
        let attribution = try await WeatherService.shared.attribution
        return WeatherAttributionInfo(
            serviceName: attribution.serviceName,
            legalPageURL: attribution.legalPageURL,
            combinedMarkLightURL: attribution.combinedMarkLightURL,
            combinedMarkDarkURL: attribution.combinedMarkDarkURL
        )
    }

    // MARK: Mapping

    static func hour(from hour: HourWeather) -> HourlyForecast {
        var snowfall: Double?
        if #available(iOS 18.0, macOS 15.0, *) {
            snowfall = hour.snowfallAmount.converted(to: .centimeters).value
        }
        return HourlyForecast(
            date: hour.date,
            condition: SkyCondition(weatherKit: hour.condition),
            isDaylight: hour.isDaylight,
            temperature: hour.temperature.converted(to: .celsius).value,
            apparentTemperature: hour.apparentTemperature.converted(to: .celsius).value,
            humidity: hour.humidity,
            dewPoint: hour.dewPoint.converted(to: .celsius).value,
            precipitationChance: hour.precipitationChance,
            precipitationAmount: hour.precipitationAmount.converted(to: .millimeters).value,
            snowfallAmount: snowfall,
            precipitationKind: precipitationKind(hour.precipitation),
            windSpeed: hour.wind.speed.converted(to: .kilometersPerHour).value,
            windGust: hour.wind.gust?.converted(to: .kilometersPerHour).value,
            windDirection: hour.wind.direction.converted(to: .degrees).value,
            uvIndex: Double(hour.uvIndex.value),
            cloudCover: hour.cloudCover,
            visibility: hour.visibility.converted(to: .kilometers).value,
            pressure: hour.pressure.converted(to: .hectopascals).value
        )
    }

    static func day(from day: DayWeather) -> DailyForecast {
        DailyForecast(
            date: day.date,
            condition: SkyCondition(weatherKit: day.condition),
            high: day.highTemperature.converted(to: .celsius).value,
            low: day.lowTemperature.converted(to: .celsius).value,
            precipitationChance: day.precipitationChance,
            precipitationAmount: day.precipitationAmount.converted(to: .millimeters).value,
            snowfallAmount: day.snowfallAmount.converted(to: .centimeters).value,
            precipitationKind: precipitationKind(day.precipitation),
            sunrise: day.sun.sunrise,
            sunset: day.sun.sunset,
            uvIndexMax: Double(day.uvIndex.value),
            windSpeedMax: day.wind.speed.converted(to: .kilometersPerHour).value,
            windGustMax: day.wind.gust?.converted(to: .kilometersPerHour).value,
            windDirectionDominant: day.wind.direction.converted(to: .degrees).value,
            moonrise: day.moon.moonrise,
            moonset: day.moon.moonset
        )
    }

    /// WeatherKit reports intensities as `UnitSpeed`; convert to a length per hour in mm.
    static func millimetersPerHour(_ measurement: Measurement<UnitSpeed>) -> Double {
        max(0, measurement.converted(to: .kilometersPerHour).value * 1_000_000)
    }

    static func precipitationKind(_ precipitation: Precipitation) -> PrecipitationKind {
        switch precipitation {
        case .none: return .none
        case .rain: return .rain
        case .snow: return .snow
        case .sleet: return .sleet
        case .hail: return .hail
        case .mixed: return .mixed
        @unknown default: return .rain
        }
    }

    static func pressureTrend(_ trend: WeatherKit.PressureTrend) -> AiSkyKit.PressureTrend {
        switch trend {
        case .rising: return .rising
        case .falling: return .falling
        case .steady: return .steady
        @unknown default: return .unknown
        }
    }

    static func severity(_ severity: WeatherSeverity) -> AlertSeverity {
        switch severity {
        case .minor: return .minor
        case .moderate: return .moderate
        case .severe: return .severe
        case .extreme: return .extreme
        case .unknown: return .unknown
        @unknown default: return .unknown
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
extension SkyCondition {
    init(weatherKit condition: WeatherCondition) {
        switch condition {
        case .blizzard: self = .blizzard
        case .blowingDust: self = .dust
        case .blowingSnow: self = .blowingSnow
        case .breezy: self = .breezy
        case .clear: self = .clear
        case .cloudy: self = .cloudy
        case .drizzle: self = .drizzle
        case .flurries: self = .flurries
        case .foggy: self = .fog
        case .freezingDrizzle: self = .freezingDrizzle
        case .freezingRain: self = .freezingRain
        case .frigid: self = .frigid
        case .hail: self = .hail
        case .haze: self = .haze
        case .heavyRain: self = .heavyRain
        case .heavySnow: self = .heavySnow
        case .hot: self = .hot
        case .hurricane: self = .hurricane
        case .isolatedThunderstorms: self = .isolatedThunderstorms
        case .mostlyClear: self = .mostlyClear
        case .mostlyCloudy: self = .mostlyCloudy
        case .partlyCloudy: self = .partlyCloudy
        case .rain: self = .rain
        case .scatteredThunderstorms: self = .scatteredThunderstorms
        case .sleet: self = .sleet
        case .smoky: self = .smoke
        case .snow: self = .snow
        case .strongStorms: self = .strongStorms
        case .sunFlurries: self = .sunFlurries
        case .sunShowers: self = .sunShowers
        case .thunderstorms: self = .thunderstorms
        case .tropicalStorm: self = .tropicalStorm
        case .windy: self = .windy
        case .wintryMix: self = .wintryMix
        @unknown default: self = .cloudy
        }
    }
}
#endif
