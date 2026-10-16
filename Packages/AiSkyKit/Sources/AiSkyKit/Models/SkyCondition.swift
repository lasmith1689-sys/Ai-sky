import Foundation

/// Kind of falling precipitation.
public enum PrecipitationKind: String, Codable, CaseIterable, Sendable {
    case none
    case rain
    case snow
    case sleet
    case hail
    case mixed

    /// Noun used in summaries: "rain", "snow", "sleet", "hail", "wintry mix".
    public var noun: String {
        switch self {
        case .none: return "precipitation"
        case .rain: return "rain"
        case .snow: return "snow"
        case .sleet: return "sleet"
        case .hail: return "hail"
        case .mixed: return "wintry mix"
        }
    }
}

/// Provider-independent description of the sky. Covers both WMO codes (Open-Meteo)
/// and Apple WeatherKit conditions.
public enum SkyCondition: String, Codable, CaseIterable, Sendable {
    case clear
    case mostlyClear
    case partlyCloudy
    case mostlyCloudy
    case cloudy
    case fog
    case haze
    case smoke
    case dust
    case breezy
    case windy
    case drizzle
    case lightRain
    case rain
    case heavyRain
    case sunShowers
    case freezingDrizzle
    case freezingRain
    case sleet
    case wintryMix
    case flurries
    case lightSnow
    case snow
    case heavySnow
    case sunFlurries
    case blowingSnow
    case blizzard
    case hail
    case isolatedThunderstorms
    case scatteredThunderstorms
    case thunderstorms
    case strongStorms
    case tropicalStorm
    case hurricane
    case hot
    case frigid

    // MARK: Descriptions

    public var description: String {
        switch self {
        case .clear: return "Clear"
        case .mostlyClear: return "Mostly Clear"
        case .partlyCloudy: return "Partly Cloudy"
        case .mostlyCloudy: return "Mostly Cloudy"
        case .cloudy: return "Cloudy"
        case .fog: return "Fog"
        case .haze: return "Haze"
        case .smoke: return "Smoke"
        case .dust: return "Blowing Dust"
        case .breezy: return "Breezy"
        case .windy: return "Windy"
        case .drizzle: return "Drizzle"
        case .lightRain: return "Light Rain"
        case .rain: return "Rain"
        case .heavyRain: return "Heavy Rain"
        case .sunShowers: return "Sun Showers"
        case .freezingDrizzle: return "Freezing Drizzle"
        case .freezingRain: return "Freezing Rain"
        case .sleet: return "Sleet"
        case .wintryMix: return "Wintry Mix"
        case .flurries: return "Flurries"
        case .lightSnow: return "Light Snow"
        case .snow: return "Snow"
        case .heavySnow: return "Heavy Snow"
        case .sunFlurries: return "Sun Flurries"
        case .blowingSnow: return "Blowing Snow"
        case .blizzard: return "Blizzard"
        case .hail: return "Hail"
        case .isolatedThunderstorms: return "Isolated Storms"
        case .scatteredThunderstorms: return "Scattered Storms"
        case .thunderstorms: return "Thunderstorms"
        case .strongStorms: return "Strong Storms"
        case .tropicalStorm: return "Tropical Storm"
        case .hurricane: return "Hurricane"
        case .hot: return "Hot"
        case .frigid: return "Frigid"
        }
    }

    /// SF Symbol name. Filled variants render nicely with `.symbolRenderingMode(.multicolor)`.
    public func symbolName(isDaylight: Bool) -> String {
        switch self {
        case .clear:
            return isDaylight ? "sun.max.fill" : "moon.stars.fill"
        case .hot:
            return "thermometer.sun.fill"
        case .mostlyClear:
            return isDaylight ? "sun.max.fill" : "moon.fill"
        case .partlyCloudy:
            return isDaylight ? "cloud.sun.fill" : "cloud.moon.fill"
        case .mostlyCloudy, .cloudy:
            return "cloud.fill"
        case .fog:
            return "cloud.fog.fill"
        case .haze:
            return isDaylight ? "sun.haze.fill" : "moon.haze.fill"
        case .smoke:
            return "smoke.fill"
        case .dust:
            return "sun.dust.fill"
        case .breezy, .windy:
            return "wind"
        case .drizzle:
            return "cloud.drizzle.fill"
        case .lightRain, .rain:
            return "cloud.rain.fill"
        case .heavyRain:
            return "cloud.heavyrain.fill"
        case .sunShowers:
            return isDaylight ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case .freezingDrizzle, .freezingRain, .sleet, .wintryMix:
            return "cloud.sleet.fill"
        case .flurries, .lightSnow, .snow, .sunFlurries:
            return "cloud.snow.fill"
        case .heavySnow, .blizzard:
            return "snowflake"
        case .blowingSnow:
            return "wind.snow"
        case .hail:
            return "cloud.hail.fill"
        case .isolatedThunderstorms, .scatteredThunderstorms:
            return isDaylight ? "cloud.sun.bolt.fill" : "cloud.moon.bolt.fill"
        case .thunderstorms, .strongStorms:
            return "cloud.bolt.rain.fill"
        case .tropicalStorm:
            return "tropicalstorm"
        case .hurricane:
            return "hurricane"
        case .frigid:
            return "thermometer.snowflake"
        }
    }

    /// Precipitation implied by the condition.
    public var precipitationKind: PrecipitationKind {
        switch self {
        case .drizzle, .lightRain, .rain, .heavyRain, .sunShowers,
             .isolatedThunderstorms, .scatteredThunderstorms, .thunderstorms, .strongStorms,
             .tropicalStorm, .hurricane:
            return .rain
        case .freezingDrizzle, .freezingRain, .sleet:
            return .sleet
        case .wintryMix:
            return .mixed
        case .flurries, .lightSnow, .snow, .heavySnow, .sunFlurries, .blowingSnow, .blizzard:
            return .snow
        case .hail:
            return .hail
        default:
            return .none
        }
    }

    public var isPrecipitation: Bool { precipitationKind != .none }

    public var isThunderstorm: Bool {
        switch self {
        case .isolatedThunderstorms, .scatteredThunderstorms, .thunderstorms, .strongStorms: return true
        default: return false
        }
    }

    /// Broad bucket used for colors, backgrounds and the Dark Sky style condition timeline.
    public var family: ConditionFamily {
        switch self {
        case .clear, .mostlyClear, .hot: return .clear
        case .partlyCloudy: return .partlyCloudy
        case .mostlyCloudy, .cloudy: return .cloudy
        case .fog, .haze, .smoke, .dust: return .fog
        case .breezy, .windy: return .windy
        case .drizzle, .lightRain: return .lightRain
        case .rain, .sunShowers: return .rain
        case .heavyRain, .tropicalStorm, .hurricane: return .heavyRain
        case .freezingDrizzle, .freezingRain, .sleet, .wintryMix, .hail: return .sleet
        case .flurries, .lightSnow, .snow, .heavySnow, .sunFlurries, .blowingSnow, .blizzard, .frigid: return .snow
        case .isolatedThunderstorms, .scatteredThunderstorms, .thunderstorms, .strongStorms: return .storm
        }
    }

    /// Relative importance when picking one condition to represent a period (higher wins).
    public var severity: Int {
        switch family {
        case .clear: return 0
        case .partlyCloudy: return 1
        case .windy: return 2
        case .cloudy: return 3
        case .fog: return 4
        case .lightRain: return 5
        case .rain: return 6
        case .snow: return 7
        case .sleet: return 7
        case .heavyRain: return 8
        case .storm: return 9
        }
    }

    // MARK: WMO weather interpretation codes (Open-Meteo)

    /// Maps a WMO weather code to a condition. Cloud cover (0...1) refines the codes 0–3,
    /// and strong wind upgrades dry conditions to breezy/windy.
    public init(wmoCode: Int, cloudCover: Double? = nil, windSpeedKmh: Double? = nil) {
        var condition: SkyCondition
        switch wmoCode {
        case 0: condition = .clear
        case 1: condition = .mostlyClear
        case 2: condition = .partlyCloudy
        case 3: condition = .cloudy
        case 45, 48: condition = .fog
        case 51, 53: condition = .drizzle
        case 55: condition = .lightRain
        case 56, 57: condition = .freezingDrizzle
        case 61: condition = .lightRain
        case 63: condition = .rain
        case 65: condition = .heavyRain
        case 66, 67: condition = .freezingRain
        case 71: condition = .flurries
        case 73: condition = .snow
        case 75: condition = .heavySnow
        case 77: condition = .lightSnow
        case 80: condition = .lightRain
        case 81: condition = .rain
        case 82: condition = .heavyRain
        case 85: condition = .lightSnow
        case 86: condition = .heavySnow
        case 95: condition = .thunderstorms
        case 96, 99: condition = .strongStorms
        default: condition = .cloudy
        }

        if (0...3).contains(wmoCode), let cloudCover {
            switch cloudCover {
            case ..<0.15: condition = .clear
            case ..<0.35: condition = .mostlyClear
            case ..<0.65: condition = .partlyCloudy
            case ..<0.88: condition = .mostlyCloudy
            default: condition = .cloudy
            }
        }

        if !condition.isPrecipitation, condition.family != .fog, let windSpeedKmh {
            if windSpeedKmh >= 45 {
                condition = .windy
            } else if windSpeedKmh >= 32 {
                condition = .breezy
            }
        }
        self = condition
    }
}

public enum ConditionFamily: String, Codable, CaseIterable, Sendable {
    case clear
    case partlyCloudy
    case cloudy
    case fog
    case windy
    case lightRain
    case rain
    case heavyRain
    case sleet
    case snow
    case storm
}

public enum PressureTrend: String, Codable, Sendable {
    case rising
    case falling
    case steady
    case unknown

    public var description: String {
        switch self {
        case .rising: return "Rising"
        case .falling: return "Falling"
        case .steady: return "Steady"
        case .unknown: return ""
        }
    }

    public var symbolName: String {
        switch self {
        case .rising: return "arrow.up.right"
        case .falling: return "arrow.down.right"
        case .steady, .unknown: return "equal"
        }
    }
}
