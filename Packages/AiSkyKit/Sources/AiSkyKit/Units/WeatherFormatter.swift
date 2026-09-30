import Foundation

/// Formats metric model values for display using the user's unit preferences.
public struct WeatherFormatter: Sendable {
    public var units: UnitPreferences
    public var locale: Locale

    public init(units: UnitPreferences, locale: Locale = .autoupdatingCurrent) {
        self.units = units
        self.locale = locale
    }

    // MARK: Temperature

    public func temperatureValue(_ celsius: Double) -> Double {
        units.temperature.convert(celsius: celsius)
    }

    /// "72°" (or "72°F" with `includeUnit`).
    public func temperature(_ celsius: Double, includeUnit: Bool = false) -> String {
        let value = Int(temperatureValue(celsius).rounded())
        let text = value == 0 ? "0" : String(value) // avoids "-0"
        return includeUnit ? "\(text)\(units.temperature.symbol)" : "\(text)°"
    }

    public func temperatureDelta(_ celsius: Double) -> String {
        let value = Int(units.temperature.convertDelta(celsius: celsius).rounded())
        return "\(value)°"
    }

    // MARK: Wind

    public func windSpeedValue(_ kmh: Double) -> Double { units.windSpeed.convert(kmh: kmh) }

    public func windSpeed(_ kmh: Double, includeUnit: Bool = true) -> String {
        let value = windSpeedValue(kmh)
        let number: String
        switch units.windSpeed {
        case .metersPerSecond:
            number = value < 10 ? decimal(value, digits: 1) : String(Int(value.rounded()))
        default:
            number = String(Int(value.rounded()))
        }
        return includeUnit ? "\(number) \(units.windSpeed.symbol)" : number
    }

    /// "12 mph NW"
    public func wind(speed kmh: Double?, direction: Double?) -> String {
        guard let kmh else { return "--" }
        if kmh < 1 { return "Calm" }
        var text = windSpeed(kmh)
        if let direction {
            text += " \(Self.compassDirection(direction))"
        }
        return text
    }

    public static func compassDirection(_ degrees: Double) -> String {
        let names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                     "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let index = Int((normalized / 22.5).rounded()) % 16
        return names[index]
    }

    public static func compassDirectionName(_ degrees: Double) -> String {
        switch compassDirection(degrees) {
        case "N": return "north"
        case "NNE": return "north-northeast"
        case "NE": return "northeast"
        case "ENE": return "east-northeast"
        case "E": return "east"
        case "ESE": return "east-southeast"
        case "SE": return "southeast"
        case "SSE": return "south-southeast"
        case "S": return "south"
        case "SSW": return "south-southwest"
        case "SW": return "southwest"
        case "WSW": return "west-southwest"
        case "W": return "west"
        case "WNW": return "west-northwest"
        case "NW": return "northwest"
        default: return "north-northwest"
        }
    }

    // MARK: Precipitation

    public func precipitationValue(_ millimeters: Double) -> Double {
        units.precipitation.convert(millimeters: millimeters)
    }

    /// "0.42 in", "10.7 mm", "<0.01 in" for traces.
    public func precipitation(_ millimeters: Double, includeUnit: Bool = true) -> String {
        let value = precipitationValue(millimeters)
        let symbol = includeUnit ? " \(units.precipitation.symbol)" : ""
        switch units.precipitation {
        case .inches:
            if millimeters > 0, value < 0.005 { return "<0.01\(symbol)" }
            return decimal(value, digits: 2) + symbol
        case .millimeters:
            if millimeters > 0, value < 0.05 { return "<0.1\(symbol)" }
            return (value >= 100 ? String(Int(value.rounded())) : decimal(value, digits: 1)) + symbol
        }
    }

    /// Snow depth: "1.5 in" or "4 cm".
    public func snowfall(_ centimeters: Double, includeUnit: Bool = true) -> String {
        let value = units.precipitation.convertSnow(centimeters: centimeters)
        let symbol = includeUnit ? " \(units.precipitation.snowSymbol)" : ""
        if centimeters > 0, value < 0.05 { return "<0.1\(symbol)" }
        return decimal(value, digits: value < 10 ? 1 : 0) + symbol
    }

    /// Rain rate: "0.10 in/hr" or "2.5 mm/h".
    public func precipitationRate(_ millimetersPerHour: Double) -> String {
        switch units.precipitation {
        case .inches: return decimal(millimetersPerHour / 25.4, digits: 2) + " in/hr"
        case .millimeters: return decimal(millimetersPerHour, digits: 1) + " mm/h"
        }
    }

    // MARK: Other measurements

    public func pressure(_ hectopascals: Double, includeUnit: Bool = true) -> String {
        let value = units.pressure.convert(hectopascals: hectopascals)
        let number: String
        switch units.pressure {
        case .inchesOfMercury: number = decimal(value, digits: 2)
        case .hectopascals, .millimetersOfMercury: number = String(Int(value.rounded()))
        }
        return includeUnit ? "\(number) \(units.pressure.symbol)" : number
    }

    public func visibility(_ kilometers: Double) -> String {
        let value = units.distance.convert(kilometers: kilometers)
        let number = value < 10 ? decimal(value, digits: 1) : String(Int(value.rounded()))
        return "\(number) \(units.distance.symbol)"
    }

    public func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// Rounds precipitation chance to the nearest 10% like most weather apps.
    public func chance(_ fraction: Double) -> String {
        "\(Int((fraction * 10).rounded() * 10))%"
    }

    public func decimal(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", locale: locale, value)
    }

    // MARK: Dates (always in the location's time zone)

    /// "3 PM" or "15" depending on the user's 12/24 hour preference.
    public func hour(_ date: Date, timeZone: TimeZone) -> String {
        FormatterCache.shared.string(from: date, template: "j", timeZone: timeZone, locale: locale)
    }

    /// "3:41 PM"
    public func time(_ date: Date, timeZone: TimeZone) -> String {
        FormatterCache.shared.string(from: date, template: "jmm", timeZone: timeZone, locale: locale)
    }

    /// "Tue"
    public func weekdayShort(_ date: Date, timeZone: TimeZone) -> String {
        FormatterCache.shared.string(from: date, template: "EEE", timeZone: timeZone, locale: locale)
    }

    /// "Tuesday"
    public func weekday(_ date: Date, timeZone: TimeZone) -> String {
        FormatterCache.shared.string(from: date, template: "EEEE", timeZone: timeZone, locale: locale)
    }

    /// "Sep 28"
    public func monthDay(_ date: Date, timeZone: TimeZone) -> String {
        FormatterCache.shared.string(from: date, template: "MMMd", timeZone: timeZone, locale: locale)
    }

    /// "Tuesday, September 30"
    public func fullDay(_ date: Date, timeZone: TimeZone) -> String {
        FormatterCache.shared.string(from: date, template: "EEEEMMMMd", timeZone: timeZone, locale: locale)
    }

    /// "Thursday, July 4, 1940"
    public func longDate(_ date: Date, timeZone: TimeZone) -> String {
        FormatterCache.shared.string(from: date, template: "EEEEMMMMdy", timeZone: timeZone, locale: locale)
    }

    /// "Jul 4, 2024"
    public func mediumDate(_ date: Date, timeZone: TimeZone) -> String {
        FormatterCache.shared.string(from: date, template: "yMMMd", timeZone: timeZone, locale: locale)
    }

    /// "Sep"
    public func monthShort(_ date: Date, timeZone: TimeZone) -> String {
        FormatterCache.shared.string(from: date, template: "MMM", timeZone: timeZone, locale: locale)
    }

    /// "Sep 2025"
    public func monthYear(_ date: Date, timeZone: TimeZone) -> String {
        FormatterCache.shared.string(from: date, template: "MMMy", timeZone: timeZone, locale: locale)
    }

    /// "2025"
    public func year(_ date: Date, timeZone: TimeZone) -> String {
        FormatterCache.shared.string(from: date, template: "y", timeZone: timeZone, locale: locale)
    }

    /// "Today", "Tomorrow", or "Tue".
    public func dayLabel(_ date: Date, timeZone: TimeZone, now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        return weekdayShort(date, timeZone: timeZone)
    }

    /// "Updated just now", "Updated 5 min ago", "Updated 2 hr ago".
    public static func updatedText(since date: Date, now: Date = Date()) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        switch minutes {
        case ..<1: return "Updated just now"
        case ..<60: return "Updated \(minutes) min ago"
        case ..<(48 * 60): return "Updated \(minutes / 60) hr ago"
        default: return "Updated \(minutes / (60 * 24)) days ago"
        }
    }

    /// "12 min", "1 hr 5 min"
    public static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int((interval / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }
}

/// Thread-safe cache of `DateFormatter`s keyed by template, time zone and locale.
final class FormatterCache: @unchecked Sendable {
    static let shared = FormatterCache()

    private var formatters: [String: DateFormatter] = [:]
    private let lock = NSLock()

    func string(from date: Date, template: String, timeZone: TimeZone, locale: Locale) -> String {
        let key = "\(template)|\(timeZone.identifier)|\(locale.identifier)"
        lock.lock()
        defer { lock.unlock() }
        let formatter: DateFormatter
        if let cached = formatters[key] {
            formatter = cached
        } else {
            formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            formatters[key] = formatter
        }
        // ICU puts a narrow no-break space before AM/PM. Most bundled typefaces lack that glyph
        // and the fallback renders a wide gap, so use a regular no-break space.
        return formatter.string(from: date).replacingOccurrences(of: "\u{202F}", with: "\u{00A0}")
    }
}
