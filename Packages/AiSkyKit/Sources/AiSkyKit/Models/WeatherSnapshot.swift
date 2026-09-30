import Foundation

/// Where a snapshot's forecast came from.
public enum WeatherDataSource: String, Codable, Sendable {
    case appleWeather
    case openMeteo

    public var displayName: String {
        switch self {
        case .appleWeather: return "Apple Weather"
        case .openMeteo: return "Open-Meteo"
        }
    }
}

/// Everything the app and widgets need to render one location.
///
/// All values are stored in metric units (°C, km/h, mm, cm of snow, hPa, km) and converted
/// for display by ``WeatherFormatter``.
public struct WeatherSnapshot: Codable, Sendable, Equatable {
    public var location: WeatherLocation
    public var fetchedAt: Date
    public var source: WeatherDataSource
    public var timeZoneIdentifier: String
    public var current: CurrentConditions
    public var nextHour: NextHourForecast?
    /// Hourly forecast. May include up to 24 past hours; use ``upcomingHours(from:limit:)``.
    public var hourly: [HourlyForecast]
    /// Daily forecast starting today (local time).
    public var daily: [DailyForecast]
    public var precipitationHistory: PrecipitationHistory?
    public var airQuality: AirQuality?
    public var alerts: [WeatherAlertInfo]
    /// Human-readable notes about data sources (e.g. fallbacks) shown in the footer.
    public var notes: [String]

    public init(
        location: WeatherLocation,
        fetchedAt: Date,
        source: WeatherDataSource,
        timeZoneIdentifier: String,
        current: CurrentConditions,
        nextHour: NextHourForecast? = nil,
        hourly: [HourlyForecast] = [],
        daily: [DailyForecast] = [],
        precipitationHistory: PrecipitationHistory? = nil,
        airQuality: AirQuality? = nil,
        alerts: [WeatherAlertInfo] = [],
        notes: [String] = []
    ) {
        self.location = location
        self.fetchedAt = fetchedAt
        self.source = source
        self.timeZoneIdentifier = timeZoneIdentifier
        self.current = current
        self.nextHour = nextHour
        self.hourly = hourly
        self.daily = daily
        self.precipitationHistory = precipitationHistory
        self.airQuality = airQuality
        self.alerts = alerts
        self.notes = notes
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    public func age(now: Date = Date()) -> TimeInterval { now.timeIntervalSince(fetchedAt) }

    public func isFresh(maxAge: TimeInterval, now: Date = Date()) -> Bool {
        age(now: now) < maxAge
    }

    /// Hours starting with the one that contains `date`.
    public func upcomingHours(from date: Date = Date(), limit: Int = 48) -> [HourlyForecast] {
        let startOfHour = date.addingTimeInterval(-3599)
        return Array(hourly.lazy.filter { $0.date > startOfHour }.prefix(limit))
    }

    /// The hour that contains `date`, if available.
    public func hour(containing date: Date) -> HourlyForecast? {
        hourly.last { $0.date <= date && date.timeIntervalSince($0.date) < 3600 }
    }

    /// The forecast day that contains `date` in the location's time zone.
    public func day(containing date: Date = Date()) -> DailyForecast? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return daily.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// Daily entries from today onwards.
    public func upcomingDays(from date: Date = Date(), limit: Int = 10) -> [DailyForecast] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: date)
        return Array(daily.lazy.filter { $0.date >= today.addingTimeInterval(-3600) }.prefix(limit))
    }

    /// Best estimate of conditions at a (possibly future) moment. Used by widget timelines so
    /// that entries scheduled later in the hour still look right if a refresh is delayed.
    public func conditions(at date: Date) -> CurrentConditions {
        guard date.timeIntervalSince(current.date) > 40 * 60, let hour = hour(containing: date) else {
            return current
        }
        return CurrentConditions(
            date: date,
            condition: hour.condition,
            isDaylight: hour.isDaylight,
            temperature: hour.temperature,
            apparentTemperature: hour.apparentTemperature ?? hour.temperature,
            humidity: hour.humidity,
            dewPoint: hour.dewPoint,
            pressure: hour.pressure,
            pressureTrend: current.pressureTrend,
            windSpeed: hour.windSpeed,
            windGust: hour.windGust,
            windDirection: hour.windDirection,
            uvIndex: hour.uvIndex,
            visibility: hour.visibility,
            cloudCover: hour.cloudCover,
            precipitationIntensity: hour.precipitationAmount
        )
    }

    /// Compact summary used by the location library and the multi-location widget.
    public var summary: LocationWeatherSummary {
        let today = day(containing: current.date) ?? daily.first
        return LocationWeatherSummary(
            locationID: location.id,
            fetchedAt: fetchedAt,
            timeZoneIdentifier: timeZoneIdentifier,
            temperature: current.temperature,
            apparentTemperature: current.apparentTemperature,
            condition: current.condition,
            isDaylight: current.isDaylight,
            high: today?.high,
            low: today?.low,
            precipitationChance: today?.precipitationChance,
            source: source
        )
    }
}

public struct CurrentConditions: Codable, Sendable, Equatable {
    public var date: Date
    public var condition: SkyCondition
    public var isDaylight: Bool
    /// °C
    public var temperature: Double
    /// "Feels like" / real-feel temperature, °C
    public var apparentTemperature: Double
    /// 0...1
    public var humidity: Double?
    /// °C
    public var dewPoint: Double?
    /// Sea-level pressure, hPa
    public var pressure: Double?
    public var pressureTrend: PressureTrend
    /// km/h
    public var windSpeed: Double?
    /// km/h
    public var windGust: Double?
    /// Meteorological direction the wind blows *from*, degrees.
    public var windDirection: Double?
    public var uvIndex: Double?
    /// km
    public var visibility: Double?
    /// 0...1
    public var cloudCover: Double?
    /// mm/h
    public var precipitationIntensity: Double?

    public init(
        date: Date,
        condition: SkyCondition,
        isDaylight: Bool,
        temperature: Double,
        apparentTemperature: Double,
        humidity: Double? = nil,
        dewPoint: Double? = nil,
        pressure: Double? = nil,
        pressureTrend: PressureTrend = .unknown,
        windSpeed: Double? = nil,
        windGust: Double? = nil,
        windDirection: Double? = nil,
        uvIndex: Double? = nil,
        visibility: Double? = nil,
        cloudCover: Double? = nil,
        precipitationIntensity: Double? = nil
    ) {
        self.date = date
        self.condition = condition
        self.isDaylight = isDaylight
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.humidity = humidity
        self.dewPoint = dewPoint
        self.pressure = pressure
        self.pressureTrend = pressureTrend
        self.windSpeed = windSpeed
        self.windGust = windGust
        self.windDirection = windDirection
        self.uvIndex = uvIndex
        self.visibility = visibility
        self.cloudCover = cloudCover
        self.precipitationIntensity = precipitationIntensity
    }
}

/// Down-to-the-minute precipitation for the next hour (Dark Sky style).
public struct NextHourForecast: Codable, Sendable, Equatable {
    public var minutes: [MinutePrecipitation]
    /// Seconds between samples: 60 for Apple Weather, 900 for Open-Meteo's 15-minute data.
    public var resolution: TimeInterval
    /// Text supplied by the provider (Apple Weather's own next-hour summary), if any.
    public var providerSummary: String?

    public init(minutes: [MinutePrecipitation], resolution: TimeInterval, providerSummary: String? = nil) {
        self.minutes = minutes.sorted { $0.date < $1.date }
        self.resolution = resolution
        self.providerSummary = providerSummary
    }

    public var isMinuteByMinute: Bool { resolution <= 60 }

    /// Samples covering `[start, start + duration)`; the sample in progress at `start` is included.
    public func window(from start: Date, duration: TimeInterval = 3600) -> [MinutePrecipitation] {
        let end = start.addingTimeInterval(duration)
        return minutes.filter { $0.date.addingTimeInterval(resolution) > start && $0.date < end }
    }
}

public struct MinutePrecipitation: Codable, Sendable, Equatable {
    /// Start of the interval the sample describes.
    public var date: Date
    /// Liquid-equivalent intensity, mm/h.
    public var intensity: Double
    /// Probability 0...1 when the provider supplies it.
    public var chance: Double?
    public var kind: PrecipitationKind

    public init(date: Date, intensity: Double, chance: Double? = nil, kind: PrecipitationKind) {
        self.date = date
        self.intensity = intensity
        self.chance = chance
        self.kind = kind
    }
}

public struct HourlyForecast: Codable, Sendable, Equatable, Identifiable {
    public var id: Date { date }
    /// Start of the hour.
    public var date: Date
    public var condition: SkyCondition
    public var isDaylight: Bool
    public var temperature: Double
    public var apparentTemperature: Double?
    public var humidity: Double?
    public var dewPoint: Double?
    /// Probability of precipitation during the hour, 0...1.
    public var precipitationChance: Double?
    /// Liquid-equivalent precipitation during the hour, mm.
    public var precipitationAmount: Double?
    /// Snowfall during the hour, cm.
    public var snowfallAmount: Double?
    public var precipitationKind: PrecipitationKind
    public var windSpeed: Double?
    public var windGust: Double?
    public var windDirection: Double?
    public var uvIndex: Double?
    public var cloudCover: Double?
    public var visibility: Double?
    public var pressure: Double?

    public init(
        date: Date,
        condition: SkyCondition,
        isDaylight: Bool,
        temperature: Double,
        apparentTemperature: Double? = nil,
        humidity: Double? = nil,
        dewPoint: Double? = nil,
        precipitationChance: Double? = nil,
        precipitationAmount: Double? = nil,
        snowfallAmount: Double? = nil,
        precipitationKind: PrecipitationKind = .none,
        windSpeed: Double? = nil,
        windGust: Double? = nil,
        windDirection: Double? = nil,
        uvIndex: Double? = nil,
        cloudCover: Double? = nil,
        visibility: Double? = nil,
        pressure: Double? = nil
    ) {
        self.date = date
        self.condition = condition
        self.isDaylight = isDaylight
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.humidity = humidity
        self.dewPoint = dewPoint
        self.precipitationChance = precipitationChance
        self.precipitationAmount = precipitationAmount
        self.snowfallAmount = snowfallAmount
        self.precipitationKind = precipitationKind
        self.windSpeed = windSpeed
        self.windGust = windGust
        self.windDirection = windDirection
        self.uvIndex = uvIndex
        self.cloudCover = cloudCover
        self.visibility = visibility
        self.pressure = pressure
    }
}

public struct DailyForecast: Codable, Sendable, Equatable, Identifiable {
    public var id: Date { date }
    /// Local midnight of the day.
    public var date: Date
    public var condition: SkyCondition
    public var high: Double
    public var low: Double
    public var apparentHigh: Double?
    public var apparentLow: Double?
    public var precipitationChance: Double?
    /// mm (liquid equivalent)
    public var precipitationAmount: Double?
    /// cm
    public var snowfallAmount: Double?
    public var precipitationHours: Double?
    public var precipitationKind: PrecipitationKind
    public var sunrise: Date?
    public var sunset: Date?
    public var uvIndexMax: Double?
    public var windSpeedMax: Double?
    public var windGustMax: Double?
    public var windDirectionDominant: Double?
    public var moonrise: Date?
    public var moonset: Date?

    public init(
        date: Date,
        condition: SkyCondition,
        high: Double,
        low: Double,
        apparentHigh: Double? = nil,
        apparentLow: Double? = nil,
        precipitationChance: Double? = nil,
        precipitationAmount: Double? = nil,
        snowfallAmount: Double? = nil,
        precipitationHours: Double? = nil,
        precipitationKind: PrecipitationKind = .none,
        sunrise: Date? = nil,
        sunset: Date? = nil,
        uvIndexMax: Double? = nil,
        windSpeedMax: Double? = nil,
        windGustMax: Double? = nil,
        windDirectionDominant: Double? = nil,
        moonrise: Date? = nil,
        moonset: Date? = nil
    ) {
        self.date = date
        self.condition = condition
        self.high = high
        self.low = low
        self.apparentHigh = apparentHigh
        self.apparentLow = apparentLow
        self.precipitationChance = precipitationChance
        self.precipitationAmount = precipitationAmount
        self.snowfallAmount = snowfallAmount
        self.precipitationHours = precipitationHours
        self.precipitationKind = precipitationKind
        self.sunrise = sunrise
        self.sunset = sunset
        self.uvIndexMax = uvIndexMax
        self.windSpeedMax = windSpeedMax
        self.windGustMax = windGustMax
        self.windDirectionDominant = windDirectionDominant
        self.moonrise = moonrise
        self.moonset = moonset
    }

    /// Moon phase for local noon of this day.
    public var moon: MoonInfo { MoonCalculator.moon(on: date.addingTimeInterval(12 * 3600)) }
}

/// Observed / analyzed precipitation for the recent past (Precip-style history).
public struct PrecipitationHistory: Codable, Sendable, Equatable {
    /// Hourly samples; `date` is the start of the hour.
    public var hourly: [PrecipitationSample]
    /// Daily totals; `date` is local midnight. Today's entry may be partial or include forecast.
    public var daily: [PrecipitationSample]

    public init(hourly: [PrecipitationSample], daily: [PrecipitationSample]) {
        self.hourly = hourly.sorted { $0.date < $1.date }
        self.daily = daily.sorted { $0.date < $1.date }
    }
}

public struct PrecipitationSample: Codable, Sendable, Equatable {
    public var date: Date
    /// mm (liquid equivalent)
    public var amount: Double
    /// cm
    public var snowfall: Double?

    public init(date: Date, amount: Double, snowfall: Double? = nil) {
        self.date = date
        self.amount = amount
        self.snowfall = snowfall
    }
}

/// Lightweight conditions used by the location list and multi-location widget.
public struct LocationWeatherSummary: Codable, Sendable, Equatable {
    public var locationID: String
    public var fetchedAt: Date
    public var timeZoneIdentifier: String
    public var temperature: Double
    public var apparentTemperature: Double?
    public var condition: SkyCondition
    public var isDaylight: Bool
    public var high: Double?
    public var low: Double?
    public var precipitationChance: Double?
    public var source: WeatherDataSource

    public init(
        locationID: String,
        fetchedAt: Date,
        timeZoneIdentifier: String,
        temperature: Double,
        apparentTemperature: Double?,
        condition: SkyCondition,
        isDaylight: Bool,
        high: Double?,
        low: Double?,
        precipitationChance: Double?,
        source: WeatherDataSource
    ) {
        self.locationID = locationID
        self.fetchedAt = fetchedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.condition = condition
        self.isDaylight = isDaylight
        self.high = high
        self.low = low
        self.precipitationChance = precipitationChance
        self.source = source
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }
}
