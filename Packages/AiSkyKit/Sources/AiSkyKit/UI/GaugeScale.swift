import Foundation

/// Scale for Instrument's range gauge: a 270° dial whose end values are chosen from the day's
/// range so the low-to-high arc and the current-temperature needle always sit comfortably inside.
///
/// Values are in display units (°F or °C). Labels fall on multiples of ``labelStep``, major ticks
/// halfway between labels and minor ticks in between.
public struct GaugeScale: Equatable, Sendable {
    public var lower: Double
    public var upper: Double
    public var labelStep: Double
    public var majorStep: Double
    public var minorStep: Double

    /// Degrees swept by the dial, starting at the lower left (135°, measured clockwise from
    /// 3 o'clock) and ending at the lower right.
    public static let sweep: Double = 270
    public static let startAngle: Double = 135

    public init(lower: Double, upper: Double, labelStep: Double, majorStep: Double, minorStep: Double) {
        self.lower = lower
        self.upper = upper
        self.labelStep = labelStep
        self.majorStep = majorStep
        self.minorStep = minorStep
    }

    /// A scale that holds `low...high` (and `current`), rounded outward to whole label steps with
    /// half a step of margin, at least four label steps wide.
    /// - Parameter labelStep: 10 for °F, 5 for °C.
    public static func fitting(low: Double, high: Double, current: Double? = nil, labelStep: Double) -> GaugeScale {
        var values = [low, high].filter(\.isFinite)
        if let current, current.isFinite { values.append(current) }
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0
        var step = labelStep
        var lower: Double
        var upper: Double
        repeat {
            let margin = step / 2
            lower = (floor((minimum - margin) / step) * step)
            upper = (ceil((maximum + margin) / step) * step)
            // Keep at least four intervals so the dial doesn't look zoomed in on a steady day.
            while (upper - lower) / step < 4 - 1e-9 {
                if minimum - lower <= upper - maximum {
                    lower -= step
                } else {
                    upper += step
                }
            }
            if (upper - lower) / step <= 8 + 1e-9 { break }
            // Very wide ranges: label every other step so the numbers stay apart.
            step *= 2
        } while true

        let span = upper - lower
        var minor = step / 10
        if span / minor > 60 { minor = step / 5 }
        return GaugeScale(lower: lower + 0, upper: upper + 0, labelStep: step, majorStep: step / 2, minorStep: minor)
    }

    public var span: Double { upper - lower }

    /// Position of `value` along the dial, 0 at the lower end and 1 at the upper end (clamped).
    public func fraction(_ value: Double) -> Double {
        guard span > 0 else { return 0 }
        return min(max((value - lower) / span, 0), 1)
    }

    /// Angle in degrees, clockwise from 3 o'clock (screen coordinates), for `value`.
    public func angle(_ value: Double) -> Double {
        Self.startAngle + Self.sweep * fraction(value)
    }

    /// Values that get a number on the dial.
    public var labels: [Double] {
        stride(from: lower, through: upper + labelStep * 1e-6, by: labelStep).map { ($0 * 1e6).rounded() / 1e6 }
    }

    public struct Tick: Equatable, Sendable {
        public var value: Double
        public var isMajor: Bool
    }

    /// Every tick from the lower to the upper end.
    public var ticks: [Tick] {
        let count = Int((span / minorStep).rounded())
        guard count > 0 else { return [] }
        return (0...count).map { index in
            let value = lower + Double(index) * minorStep
            let steps = (value - lower) / majorStep
            return Tick(value: value, isMajor: abs(steps - steps.rounded()) < 1e-6)
        }
    }
}

/// Short uppercase qualifiers for the stat tiles ("MOD", "GOOD").
public enum InstrumentAbbreviation {
    public static func uv(_ category: UVCategory) -> String {
        switch category {
        case .low: return "LOW"
        case .moderate: return "MOD"
        case .high: return "HIGH"
        case .veryHigh: return "V.HIGH"
        case .extreme: return "EXTR"
        }
    }

    public static func aqi(_ level: AQILevel) -> String {
        switch (level.scale, level.rank) {
        case (.us, 0), (.european, 0): return "GOOD"
        case (.us, 1): return "MOD"
        case (.us, 2): return "USG"
        case (.us, 3): return "UNHLTHY"
        case (.us, 4): return "V.UNHL"
        case (.us, _): return "HAZ"
        case (.european, 1): return "FAIR"
        case (.european, 2): return "MOD"
        case (.european, 3): return "POOR"
        case (.european, 4): return "V.POOR"
        default: return "EXTR"
        }
    }
}

extension MinuteChartData {
    /// Display value (see ``PrecipitationIntensity/chartValue(millimetersPerHour:)``) at or above
    /// which a bar counts as precipitating: the "very light" threshold of 0.03 mm/h.
    public static let wetThreshold = PrecipitationIntensity.chartValue(millimetersPerHour: 0.03)

    /// The next hour as `count` bars (2 minutes each for 30 bars), each the peak display value
    /// (0...1.1) within its slice.
    public static func bars(for forecast: NextHourForecast, now: Date, count: Int = 30) -> [Double] {
        guard count > 0 else { return [] }
        let samples = Self.points(for: forecast, now: now)
        let width = 60.0 / Double(count)
        return (0..<count).map { index in
            let start = Double(index) * width
            let end = start + width
            let inSlice = samples.filter { $0.minute >= start && ($0.minute < end || (index == count - 1 && $0.minute <= end)) }
            return inSlice.map(\.value).max() ?? 0
        }
    }
}
