#if canImport(SwiftUI)
import SwiftUI

/// Colors shared by the app and widgets.
public enum Palette {
    public static func color(hex: UInt32, opacity: Double = 1) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    // MARK: Temperature

    /// Color stops keyed by °C, from frigid purple to scorching red.
    static let temperatureStops: [(celsius: Double, hex: UInt32)] = [
        (-25, 0x8E7CC3), (-15, 0x6A5ACD), (-5, 0x4D7CFE), (3, 0x3BB2F5), (10, 0x4CD4B0),
        (16, 0x8FD86A), (21, 0xF4D35E), (26, 0xF7A541), (31, 0xF26B38), (36, 0xE0303A), (42, 0xA3123A),
    ]

    public static func temperature(_ celsius: Double) -> Color {
        let stops = temperatureStops
        guard let upperIndex = stops.firstIndex(where: { $0.celsius >= celsius }) else {
            return color(hex: stops.last!.hex)
        }
        guard upperIndex > 0 else { return color(hex: stops[0].hex) }
        let lower = stops[upperIndex - 1]
        let upper = stops[upperIndex]
        let t = (celsius - lower.celsius) / (upper.celsius - lower.celsius)
        return mix(lower.hex, upper.hex, t)
    }

    /// Gradient spanning `low...high` °C, used for range bars and temperature charts.
    public static func temperatureGradient(low: Double, high: Double) -> LinearGradient {
        let steps = 5
        let colors = (0...steps).map { temperature(low + (high - low) * Double($0) / Double(steps)) }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> Color {
        let t = min(max(t, 0), 1)
        func channel(_ value: UInt32, _ shift: UInt32) -> Double { Double((value >> shift) & 0xFF) / 255 }
        return Color(
            .sRGB,
            red: channel(a, 16) + (channel(b, 16) - channel(a, 16)) * t,
            green: channel(a, 8) + (channel(b, 8) - channel(a, 8)) * t,
            blue: channel(a, 0) + (channel(b, 0) - channel(a, 0)) * t,
            opacity: 1
        )
    }

    // MARK: Precipitation

    public static let rain = color(hex: 0x4FA3FF)
    public static let heavyRain = color(hex: 0x2F5BEA)
    public static let snow = color(hex: 0xC9D8FF)
    public static let sleet = color(hex: 0x9AA8FF)
    public static let storm = color(hex: 0x8C5CF6)

    public static func precipitation(_ kind: PrecipitationKind) -> Color {
        switch kind {
        case .snow: return snow
        case .sleet, .mixed, .hail: return sleet
        case .rain, .none: return rain
        }
    }

    // MARK: Air quality & UV

    public static func aqi(_ level: AQILevel) -> Color { color(hex: level.colorHex) }

    public static func uv(_ category: UVCategory) -> Color { color(hex: category.colorHex) }

    public static func alert(_ severity: AlertSeverity) -> Color { color(hex: severity.colorHex) }

    // MARK: Conditions

    /// Dark Sky style timeline colors: pale for clear, grays for clouds, blues for rain.
    public static func conditionBar(_ family: ConditionFamily) -> Color {
        switch family {
        case .clear: return color(hex: 0xE8EEF5, opacity: 0.35)
        case .partlyCloudy: return color(hex: 0xB9C4D0, opacity: 0.55)
        case .cloudy: return color(hex: 0x8C97A4, opacity: 0.8)
        case .fog: return color(hex: 0xA7A39A, opacity: 0.8)
        case .windy: return color(hex: 0x9FC5C1, opacity: 0.7)
        case .lightRain: return color(hex: 0x7FB8FF)
        case .rain: return color(hex: 0x4F8FF7)
        case .heavyRain: return color(hex: 0x2F5BEA)
        case .sleet: return color(hex: 0x9AA8FF)
        case .snow: return color(hex: 0xDCE6FF)
        case .storm: return color(hex: 0x7B5CF0)
        }
    }

    /// Full-screen sky background for a condition.
    public static func skyGradient(for condition: SkyCondition, isDaylight: Bool) -> LinearGradient {
        let colors: [UInt32]
        switch (condition.family, isDaylight) {
        case (.clear, true): colors = [0x2E7BD6, 0x5EA8F2, 0x9CCBF7]
        case (.clear, false): colors = [0x0B1026, 0x1B2552, 0x2E3C78]
        case (.partlyCloudy, true): colors = [0x3C7CC4, 0x6E9FD6, 0xA9C4E4]
        case (.partlyCloudy, false): colors = [0x10162E, 0x252F57, 0x3D4870]
        case (.cloudy, true), (.windy, true): colors = [0x5D6D82, 0x7F8EA2, 0xA6B1BF]
        case (.cloudy, false), (.windy, false): colors = [0x1A1F2B, 0x2E3545, 0x454D60]
        case (.fog, true): colors = [0x7D8590, 0x9BA2AA, 0xBFC3C8]
        case (.fog, false): colors = [0x22262D, 0x3A3F48, 0x51565F]
        case (.lightRain, true), (.rain, true): colors = [0x3F5670, 0x5A7089, 0x7C8FA4]
        case (.lightRain, false), (.rain, false): colors = [0x121A26, 0x223044, 0x34465E]
        case (.heavyRain, _): colors = [0x1D2A3C, 0x2F4058, 0x475C78]
        case (.storm, _): colors = [0x1E1B33, 0x352F57, 0x4C4470]
        case (.sleet, true), (.snow, true): colors = [0x7D93AD, 0xA3B5CA, 0xCAD6E4]
        case (.sleet, false), (.snow, false): colors = [0x1E2635, 0x364257, 0x51607A]
        }
        return LinearGradient(colors: colors.map { color(hex: $0) }, startPoint: .top, endPoint: .bottom)
    }
}
#endif
