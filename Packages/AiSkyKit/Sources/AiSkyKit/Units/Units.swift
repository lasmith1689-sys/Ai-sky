import Foundation

public enum TemperatureUnit: String, Codable, CaseIterable, Sendable, Identifiable {
    case fahrenheit
    case celsius

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .fahrenheit: return "°F"
        case .celsius: return "°C"
        }
    }

    public var displayName: String {
        switch self {
        case .fahrenheit: return "Fahrenheit (°F)"
        case .celsius: return "Celsius (°C)"
        }
    }

    public func convert(celsius: Double) -> Double {
        switch self {
        case .fahrenheit: return celsius * 9 / 5 + 32
        case .celsius: return celsius
        }
    }

    /// Converts a temperature *difference*.
    public func convertDelta(celsius: Double) -> Double {
        switch self {
        case .fahrenheit: return celsius * 9 / 5
        case .celsius: return celsius
        }
    }
}

public enum WindSpeedUnit: String, Codable, CaseIterable, Sendable, Identifiable {
    case mph
    case kmh
    case metersPerSecond
    case knots
    case beaufort

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .mph: return "mph"
        case .kmh: return "km/h"
        case .metersPerSecond: return "m/s"
        case .knots: return "kn"
        case .beaufort: return "Bft"
        }
    }

    public var displayName: String {
        switch self {
        case .mph: return "Miles per hour (mph)"
        case .kmh: return "Kilometers per hour (km/h)"
        case .metersPerSecond: return "Meters per second (m/s)"
        case .knots: return "Knots (kn)"
        case .beaufort: return "Beaufort scale"
        }
    }

    public func convert(kmh: Double) -> Double {
        switch self {
        case .mph: return kmh * 0.621371
        case .kmh: return kmh
        case .metersPerSecond: return kmh / 3.6
        case .knots: return kmh * 0.539957
        case .beaufort: return Double(Self.beaufortNumber(kmh: kmh))
        }
    }

    public static func beaufortNumber(kmh: Double) -> Int {
        let ms = kmh / 3.6
        let limits: [Double] = [0.5, 1.6, 3.4, 5.5, 8.0, 10.8, 13.9, 17.2, 20.8, 24.5, 28.5, 32.7]
        return limits.firstIndex { ms < $0 } ?? 12
    }

    public static func beaufortDescription(kmh: Double) -> String {
        let names = ["Calm", "Light air", "Light breeze", "Gentle breeze", "Moderate breeze", "Fresh breeze",
                     "Strong breeze", "Near gale", "Gale", "Strong gale", "Storm", "Violent storm", "Hurricane force"]
        return names[beaufortNumber(kmh: kmh)]
    }
}

public enum PrecipitationUnit: String, Codable, CaseIterable, Sendable, Identifiable {
    case inches
    case millimeters

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .inches: return "in"
        case .millimeters: return "mm"
        }
    }

    public var snowSymbol: String {
        switch self {
        case .inches: return "in"
        case .millimeters: return "cm"
        }
    }

    public var displayName: String {
        switch self {
        case .inches: return "Inches (in)"
        case .millimeters: return "Millimeters (mm)"
        }
    }

    public func convert(millimeters: Double) -> Double {
        switch self {
        case .inches: return millimeters / 25.4
        case .millimeters: return millimeters
        }
    }

    /// Snow depth: inches, or centimeters for metric users.
    public func convertSnow(centimeters: Double) -> Double {
        switch self {
        case .inches: return centimeters / 2.54
        case .millimeters: return centimeters
        }
    }
}

public enum PressureUnit: String, Codable, CaseIterable, Sendable, Identifiable {
    case inchesOfMercury
    case hectopascals
    case millimetersOfMercury

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .inchesOfMercury: return "inHg"
        case .hectopascals: return "hPa"
        case .millimetersOfMercury: return "mmHg"
        }
    }

    public var displayName: String {
        switch self {
        case .inchesOfMercury: return "Inches of mercury (inHg)"
        case .hectopascals: return "Hectopascals / millibars (hPa)"
        case .millimetersOfMercury: return "Millimeters of mercury (mmHg)"
        }
    }

    public func convert(hectopascals: Double) -> Double {
        switch self {
        case .inchesOfMercury: return hectopascals * 0.0295299830714
        case .hectopascals: return hectopascals
        case .millimetersOfMercury: return hectopascals * 0.750061683
        }
    }
}

public enum DistanceUnit: String, Codable, CaseIterable, Sendable, Identifiable {
    case miles
    case kilometers

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .miles: return "mi"
        case .kilometers: return "km"
        }
    }

    public var displayName: String {
        switch self {
        case .miles: return "Miles (mi)"
        case .kilometers: return "Kilometers (km)"
        }
    }

    public func convert(kilometers: Double) -> Double {
        switch self {
        case .miles: return kilometers * 0.621371
        case .kilometers: return kilometers
        }
    }
}

public struct UnitPreferences: Codable, Sendable, Equatable {
    public var temperature: TemperatureUnit
    public var windSpeed: WindSpeedUnit
    public var precipitation: PrecipitationUnit
    public var pressure: PressureUnit
    public var distance: DistanceUnit

    public init(
        temperature: TemperatureUnit,
        windSpeed: WindSpeedUnit,
        precipitation: PrecipitationUnit,
        pressure: PressureUnit,
        distance: DistanceUnit
    ) {
        self.temperature = temperature
        self.windSpeed = windSpeed
        self.precipitation = precipitation
        self.pressure = pressure
        self.distance = distance
    }

    public static let imperial = UnitPreferences(
        temperature: .fahrenheit, windSpeed: .mph, precipitation: .inches,
        pressure: .inchesOfMercury, distance: .miles
    )

    public static let metric = UnitPreferences(
        temperature: .celsius, windSpeed: .kmh, precipitation: .millimeters,
        pressure: .hectopascals, distance: .kilometers
    )

    /// U.K. style: Celsius, mph, mm, hPa, miles.
    public static let uk = UnitPreferences(
        temperature: .celsius, windSpeed: .mph, precipitation: .millimeters,
        pressure: .hectopascals, distance: .miles
    )

    /// Picks sensible defaults for the user's region.
    public static func defaults(for locale: Locale) -> UnitPreferences {
        let region = locale.region?.identifier.uppercased() ?? ""
        if ["US", "LR", "MM", "PR", "GU", "VI", "AS", "MP", "BS", "BZ", "KY", "PW", "FM", "MH"].contains(region) {
            return .imperial
        }
        if region == "GB" {
            return .uk
        }
        return .metric
    }
}
