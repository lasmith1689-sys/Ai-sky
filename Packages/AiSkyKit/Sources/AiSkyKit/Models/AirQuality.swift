import Foundation

/// Which air-quality index to show.
public enum AQIScale: String, Codable, CaseIterable, Sendable {
    case us
    case european

    public var displayName: String {
        switch self {
        case .us: return "US AQI (EPA)"
        case .european: return "European AQI"
        }
    }

    public var shortName: String {
        switch self {
        case .us: return "AQI"
        case .european: return "EAQI"
        }
    }

    /// Upper bound used when drawing gauges.
    public var gaugeMaximum: Double {
        switch self {
        case .us: return 300
        case .european: return 100
        }
    }

    public func level(for value: Double) -> AQILevel {
        let levels = AQILevel.levels(for: self)
        return levels.last { value >= $0.lowerBound } ?? levels[0]
    }
}

/// A band of an AQI scale (e.g. US "Moderate", 51–100).
public struct AQILevel: Sendable, Equatable, Hashable {
    public var scale: AQIScale
    /// 0 = best.
    public var rank: Int
    public var name: String
    public var lowerBound: Double
    public var upperBound: Double?
    /// 0xRRGGBB
    public var colorHex: UInt32
    public var advice: String

    public static func levels(for scale: AQIScale) -> [AQILevel] {
        switch scale {
        case .us: return usLevels
        case .european: return europeanLevels
        }
    }

    public static let usLevels: [AQILevel] = [
        AQILevel(scale: .us, rank: 0, name: "Good", lowerBound: 0, upperBound: 50, colorHex: 0x00E400,
                 advice: "Air quality is satisfactory, and air pollution poses little or no risk."),
        AQILevel(scale: .us, rank: 1, name: "Moderate", lowerBound: 51, upperBound: 100, colorHex: 0xFFFF00,
                 advice: "Air quality is acceptable. Unusually sensitive people should consider reducing prolonged or heavy exertion outdoors."),
        AQILevel(scale: .us, rank: 2, name: "Unhealthy for Sensitive Groups", lowerBound: 101, upperBound: 150, colorHex: 0xFF7E00,
                 advice: "People with heart or lung disease, older adults, children, and teens should reduce prolonged or heavy exertion outdoors."),
        AQILevel(scale: .us, rank: 3, name: "Unhealthy", lowerBound: 151, upperBound: 200, colorHex: 0xFF0000,
                 advice: "Everyone may begin to experience health effects. Sensitive groups should avoid prolonged or heavy exertion outdoors."),
        AQILevel(scale: .us, rank: 4, name: "Very Unhealthy", lowerBound: 201, upperBound: 300, colorHex: 0x8F3F97,
                 advice: "Health alert: the risk of health effects is increased for everyone. Avoid prolonged or heavy exertion outdoors."),
        AQILevel(scale: .us, rank: 5, name: "Hazardous", lowerBound: 301, upperBound: nil, colorHex: 0x7E0023,
                 advice: "Health warning of emergency conditions: everyone should avoid all outdoor exertion."),
    ]

    public static let europeanLevels: [AQILevel] = [
        AQILevel(scale: .european, rank: 0, name: "Good", lowerBound: 0, upperBound: 20, colorHex: 0x50F0E6,
                 advice: "The air quality is good. Enjoy your usual outdoor activities."),
        AQILevel(scale: .european, rank: 1, name: "Fair", lowerBound: 20, upperBound: 40, colorHex: 0x50CCAA,
                 advice: "Enjoy your usual outdoor activities."),
        AQILevel(scale: .european, rank: 2, name: "Moderate", lowerBound: 40, upperBound: 60, colorHex: 0xF0E641,
                 advice: "Sensitive people should consider reducing intense outdoor activities if they experience symptoms."),
        AQILevel(scale: .european, rank: 3, name: "Poor", lowerBound: 60, upperBound: 80, colorHex: 0xFF5050,
                 advice: "Consider reducing intense activities outdoors if you experience symptoms such as sore eyes, cough or sore throat."),
        AQILevel(scale: .european, rank: 4, name: "Very Poor", lowerBound: 80, upperBound: 100, colorHex: 0x960032,
                 advice: "Reduce physical activities outdoors, particularly if you experience symptoms."),
        AQILevel(scale: .european, rank: 5, name: "Extremely Poor", lowerBound: 100, upperBound: nil, colorHex: 0x7D2181,
                 advice: "Reduce physical activities outdoors."),
    ]
}

public enum Pollutant: String, Codable, CaseIterable, Sendable {
    case pm2_5
    case pm10
    case ozone
    case nitrogenDioxide
    case sulphurDioxide
    case carbonMonoxide

    /// Chemical/short name, e.g. "PM2.5", "O₃".
    public var symbol: String {
        switch self {
        case .pm2_5: return "PM2.5"
        case .pm10: return "PM10"
        case .ozone: return "O₃"
        case .nitrogenDioxide: return "NO₂"
        case .sulphurDioxide: return "SO₂"
        case .carbonMonoxide: return "CO"
        }
    }

    public var name: String {
        switch self {
        case .pm2_5: return "Fine particles"
        case .pm10: return "Coarse particles"
        case .ozone: return "Ozone"
        case .nitrogenDioxide: return "Nitrogen dioxide"
        case .sulphurDioxide: return "Sulfur dioxide"
        case .carbonMonoxide: return "Carbon monoxide"
        }
    }

    public var about: String {
        switch self {
        case .pm2_5: return "Tiny particles from smoke, exhaust and industry that can reach deep into the lungs."
        case .pm10: return "Dust, pollen and mold particles that can irritate the airways."
        case .ozone: return "Forms when sunlight reacts with pollution; highest on hot, sunny afternoons."
        case .nitrogenDioxide: return "Mostly from traffic and burning fuel."
        case .sulphurDioxide: return "Mostly from power plants and industrial activity."
        case .carbonMonoxide: return "Colorless gas from vehicles and incomplete combustion."
        }
    }
}

public struct PollutantReading: Codable, Sendable, Equatable, Identifiable {
    public var id: Pollutant { pollutant }
    public var pollutant: Pollutant
    /// μg/m³
    public var concentration: Double
    public var usAQI: Double?
    public var europeanAQI: Double?

    public init(pollutant: Pollutant, concentration: Double, usAQI: Double? = nil, europeanAQI: Double? = nil) {
        self.pollutant = pollutant
        self.concentration = concentration
        self.usAQI = usAQI
        self.europeanAQI = europeanAQI
    }

    public func index(for scale: AQIScale) -> Double? {
        scale == .us ? usAQI : europeanAQI
    }
}

public enum PollenType: String, Codable, CaseIterable, Sendable {
    case alder
    case birch
    case grass
    case mugwort
    case olive
    case ragweed

    public var displayName: String { rawValue.capitalized }

    /// Thresholds (grains/m³) for moderate, high and very high, following U.S. National
    /// Allergy Bureau guidance for trees, grasses and weeds.
    var thresholds: (moderate: Double, high: Double, veryHigh: Double) {
        switch self {
        case .alder, .birch, .olive: return (15, 90, 1500)
        case .grass: return (5, 20, 200)
        case .mugwort, .ragweed: return (10, 50, 500)
        }
    }
}

public struct PollenReading: Codable, Sendable, Equatable, Identifiable {
    public var id: PollenType { type }
    public var type: PollenType
    /// grains/m³
    public var concentration: Double

    public init(type: PollenType, concentration: Double) {
        self.type = type
        self.concentration = concentration
    }

    public var level: PollenLevel {
        let t = type.thresholds
        switch concentration {
        case ..<1: return .none
        case ..<t.moderate: return .low
        case ..<t.high: return .moderate
        case ..<t.veryHigh: return .high
        default: return .veryHigh
        }
    }
}

public enum PollenLevel: Int, Codable, Sendable, Comparable {
    case none, low, moderate, high, veryHigh

    public var name: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        case .veryHigh: return "Very High"
        }
    }

    public static func < (lhs: PollenLevel, rhs: PollenLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct AQIForecastPoint: Codable, Sendable, Equatable {
    public var date: Date
    public var usAQI: Double?
    public var europeanAQI: Double?

    public init(date: Date, usAQI: Double?, europeanAQI: Double?) {
        self.date = date
        self.usAQI = usAQI
        self.europeanAQI = europeanAQI
    }

    public func index(for scale: AQIScale) -> Double? { scale == .us ? usAQI : europeanAQI }
}

public struct AirQuality: Codable, Sendable, Equatable {
    public var date: Date
    public var usAQI: Double?
    public var europeanAQI: Double?
    public var pollutants: [PollutantReading]
    public var pollen: [PollenReading]
    /// Saharan / desert dust, μg/m³
    public var dust: Double?
    public var hourly: [AQIForecastPoint]

    public init(
        date: Date,
        usAQI: Double?,
        europeanAQI: Double?,
        pollutants: [PollutantReading],
        pollen: [PollenReading] = [],
        dust: Double? = nil,
        hourly: [AQIForecastPoint] = []
    ) {
        self.date = date
        self.usAQI = usAQI
        self.europeanAQI = europeanAQI
        self.pollutants = pollutants
        self.pollen = pollen
        self.dust = dust
        self.hourly = hourly
    }

    public func index(for scale: AQIScale) -> Double? {
        scale == .us ? usAQI : europeanAQI
    }

    public func level(for scale: AQIScale) -> AQILevel? {
        index(for: scale).map { scale.level(for: $0) }
    }

    /// The pollutant driving the index (highest sub-index).
    public func primaryPollutant(for scale: AQIScale) -> Pollutant? {
        pollutants
            .compactMap { reading in reading.index(for: scale).map { (reading.pollutant, $0) } }
            .max { $0.1 < $1.1 }?.0
    }

    /// Daily maxima of the hourly index for the coming days (in the given time zone).
    public func dailyMaxima(for scale: AQIScale, timeZone: TimeZone, from now: Date = Date(), days: Int = 5) -> [(date: Date, value: Double)] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        var maxima: [Date: Double] = [:]
        for point in hourly {
            guard let value = point.index(for: scale) else { continue }
            let day = calendar.startOfDay(for: point.date)
            guard day >= today else { continue }
            maxima[day] = max(maxima[day] ?? -1, value)
        }
        return maxima.keys.sorted().prefix(days).map { ($0, maxima[$0]!) }
    }
}
