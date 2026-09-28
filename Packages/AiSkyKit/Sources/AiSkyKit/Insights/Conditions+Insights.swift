import Foundation

/// Explains why the "feels like" (real feel) temperature differs from the air temperature.
public enum FeelsLikeInsight {
    public static func explanation(
        temperature: Double,
        apparentTemperature: Double,
        humidity: Double?,
        windSpeed: Double?,
        isDaylight: Bool
    ) -> String {
        let difference = apparentTemperature - temperature
        if abs(difference) < 1.2 {
            return "Similar to the actual temperature."
        }
        if difference > 0 {
            if let humidity, humidity >= 0.45, temperature >= 20 {
                return "Humidity is making it feel warmer."
            }
            if isDaylight {
                return "Sunshine is making it feel warmer."
            }
            return "It feels warmer than the actual temperature."
        }
        if let windSpeed, windSpeed >= 8 {
            return "Wind is making it feel colder."
        }
        if let humidity, humidity < 0.35 {
            return "Dry air is making it feel cooler."
        }
        return "It feels colder than the actual temperature."
    }
}

public enum UVCategory: Int, Sendable, Comparable {
    case low, moderate, high, veryHigh, extreme

    public init(index: Double) {
        switch index.rounded() {
        case ..<3: self = .low
        case ..<6: self = .moderate
        case ..<8: self = .high
        case ..<11: self = .veryHigh
        default: self = .extreme
        }
    }

    public var name: String {
        switch self {
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        case .veryHigh: return "Very High"
        case .extreme: return "Extreme"
        }
    }

    /// 0xRRGGBB, WHO UV index colors.
    public var colorHex: UInt32 {
        switch self {
        case .low: return 0x3EA72D
        case .moderate: return 0xFFF300
        case .high: return 0xF18B00
        case .veryHigh: return 0xE53210
        case .extreme: return 0xB567A4
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// "Use sun protection 10 AM–4 PM." based on hours with UV ≥ 3.
    public static func protectionAdvice(hours: [HourlyForecast], day: Date, timeZone: TimeZone, formatter: WeatherFormatter) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let sameDay = hours.filter { calendar.isDate($0.date, inSameDayAs: day) }
        let high = sameDay.filter { ($0.uvIndex ?? 0) >= 2.5 }
        guard let first = high.first, let last = high.last else {
            return "Low for the rest of the day."
        }
        let start = formatter.hour(first.date, timeZone: timeZone)
        let end = formatter.hour(last.date.addingTimeInterval(3600), timeZone: timeZone)
        return "Use sun protection \(start)–\(end)."
    }
}

public enum HumidityInsight {
    public static func dewPointText(_ dewPoint: Double?, formatter: WeatherFormatter) -> String {
        guard let dewPoint else { return "" }
        let comfort: String
        switch dewPoint {
        case ..<10: comfort = "Dry and comfortable."
        case ..<16: comfort = "Comfortable."
        case ..<18: comfort = "Slightly humid."
        case ..<21: comfort = "Humid and a bit sticky."
        case ..<24: comfort = "Muggy and uncomfortable."
        default: comfort = "Oppressively humid."
        }
        return "The dew point is \(formatter.temperature(dewPoint)) right now. \(comfort)"
    }
}

public enum VisibilityInsight {
    public static func description(kilometers: Double) -> String {
        switch kilometers {
        case ..<1: return "Very poor visibility."
        case ..<4: return "Reduced visibility."
        case ..<10: return "Haze is affecting visibility."
        case ..<20: return "Good visibility."
        default: return "Perfectly clear view."
        }
    }
}
