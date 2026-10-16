import Foundation

public enum LunarPhase: String, Codable, CaseIterable, Sendable {
    case newMoon
    case waxingCrescent
    case firstQuarter
    case waxingGibbous
    case fullMoon
    case waningGibbous
    case lastQuarter
    case waningCrescent

    public var name: String {
        switch self {
        case .newMoon: return "New Moon"
        case .waxingCrescent: return "Waxing Crescent"
        case .firstQuarter: return "First Quarter"
        case .waxingGibbous: return "Waxing Gibbous"
        case .fullMoon: return "Full Moon"
        case .waningGibbous: return "Waning Gibbous"
        case .lastQuarter: return "Last Quarter"
        case .waningCrescent: return "Waning Crescent"
        }
    }

    public var symbolName: String {
        switch self {
        case .newMoon: return "moonphase.new.moon"
        case .waxingCrescent: return "moonphase.waxing.crescent"
        case .firstQuarter: return "moonphase.first.quarter"
        case .waxingGibbous: return "moonphase.waxing.gibbous"
        case .fullMoon: return "moonphase.full.moon"
        case .waningGibbous: return "moonphase.waning.gibbous"
        case .lastQuarter: return "moonphase.last.quarter"
        case .waningCrescent: return "moonphase.waning.crescent"
        }
    }
}

public struct MoonInfo: Sendable, Equatable {
    public var phase: LunarPhase
    /// Illuminated fraction of the disk, 0...1.
    public var illumination: Double
    /// Days since the last new moon.
    public var age: Double
    public var nextFullMoon: Date
    public var nextNewMoon: Date
}

/// Mean-lunation moon phase (accurate to within about half a day — plenty for display).
public enum MoonCalculator {
    public static let synodicMonth = 29.530588853
    /// New moon of 2000-01-06 18:14 UTC.
    static let referenceNewMoon = Date(timeIntervalSince1970: 947_182_440)

    public static func moon(on date: Date) -> MoonInfo {
        let days = date.timeIntervalSince(referenceNewMoon) / 86_400
        var age = days.truncatingRemainder(dividingBy: synodicMonth)
        if age < 0 { age += synodicMonth }
        let fraction = age / synodicMonth
        let illumination = (1 - cos(2 * .pi * fraction)) / 2

        let phase: LunarPhase
        switch age {
        case ..<1.0: phase = .newMoon
        case ..<6.38: phase = .waxingCrescent
        case ..<8.38: phase = .firstQuarter
        case ..<13.77: phase = .waxingGibbous
        case ..<15.77: phase = .fullMoon
        case ..<21.15: phase = .waningGibbous
        case ..<23.15: phase = .lastQuarter
        case ..<28.53: phase = .waningCrescent
        default: phase = .newMoon
        }

        let halfMonth = synodicMonth / 2
        let daysToFull = age < halfMonth ? halfMonth - age : synodicMonth - age + halfMonth
        let daysToNew = synodicMonth - age
        return MoonInfo(
            phase: phase,
            illumination: illumination,
            age: age,
            nextFullMoon: date.addingTimeInterval(daysToFull * 86_400),
            nextNewMoon: date.addingTimeInterval(daysToNew * 86_400)
        )
    }
}
