import Foundation

/// Precipitation intensity buckets modeled on Dark Sky's guidance: very light ≈ 0.002 in/h,
/// light ≈ 0.017 in/h, moderate ≈ 0.1 in/h, heavy ≈ 0.4 in/h. Bucket edges sit halfway
/// (geometrically) between those reference rates.
public enum PrecipitationIntensity: Int, Comparable, Sendable, CaseIterable {
    case none
    case veryLight
    case light
    case moderate
    case heavy

    /// Reference rates in mm/h used for the chart guide lines.
    public static let lightRate = 0.43
    public static let moderateRate = 2.54
    public static let heavyRate = 10.16

    public init(millimetersPerHour rate: Double) {
        switch rate {
        case ..<0.03: self = .none
        case ..<0.15: self = .veryLight
        case ..<1.05: self = .light
        case ..<5.08: self = .moderate
        default: self = .heavy
        }
    }

    /// Adjective for summaries. Moderate precipitation is just "Rain".
    public var adjective: String? {
        switch self {
        case .none, .moderate: return nil
        case .veryLight: return "very light"
        case .light: return "light"
        case .heavy: return "heavy"
        }
    }

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .veryLight: return "Very Light"
        case .light: return "Light"
        case .moderate: return "Moderate"
        case .heavy: return "Heavy"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Maps a rate onto 0...1 for charts: LIGHT at ⅓, MED at ⅔, HEAVY at 1 (like Dark Sky's graph).
    public static func chartValue(millimetersPerHour rate: Double) -> Double {
        let anchors: [(Double, Double)] = [(0, 0), (lightRate, 1.0 / 3), (moderateRate, 2.0 / 3), (heavyRate, 1)]
        guard rate > 0 else { return 0 }
        for i in 1..<anchors.count where rate <= anchors[i].0 {
            let (x0, y0) = anchors[i - 1]
            let (x1, y1) = anchors[i]
            return y0 + (rate - x0) / (x1 - x0) * (y1 - y0)
        }
        return min(1.1, 1 + (rate - heavyRate) / (heavyRate * 4))
    }
}

/// Plain-language summary of the next hour of precipitation.
public struct NextHourSummary: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case dry
        case starting
        case stopping
        case continuing
        case unavailable
    }

    public var state: State
    /// "Light rain starting in 12 min, stopping 25 min later."
    public var text: String
    /// Compact form for widgets: "Rain in 12 min", "Rain ending in 20 min", "Dry for the next hour".
    public var shortText: String
    public var startsIn: TimeInterval?
    public var endsIn: TimeInterval?
    public var intensity: PrecipitationIntensity
    public var precipitationKind: PrecipitationKind
    public var isPossibleOnly: Bool

    public var isPrecipitationExpected: Bool {
        state == .starting || state == .stopping || state == .continuing
    }
}

public enum NextHourSummarizer {
    /// Minimum probability for a sample to count as precipitating.
    static let possibleChance = 0.25
    static let likelyChance = 0.5

    public static func summarize(
        _ forecast: NextHourForecast?,
        now: Date = Date(),
        preferProviderText: Bool = true
    ) -> NextHourSummary {
        guard let forecast else { return unavailable }
        let window = forecast.window(from: now, duration: 3600)
        guard !window.isEmpty else { return unavailable }

        let resolution = forecast.resolution
        let coarse = resolution > 120
        let wet = window.map(isWet)
        // Ignore brief blips: minute data needs a few consecutive samples to count as a change.
        let minRun = coarse ? 1 : 3

        func offset(_ index: Int) -> TimeInterval {
            max(0, window[index].date.timeIntervalSince(now))
        }
        func firstRun(of value: Bool, from start: Int) -> Int? {
            var index = start
            while index < wet.count {
                if wet[index] == value {
                    var end = index
                    while end < wet.count, wet[end] == value { end += 1 }
                    if end - index >= minRun || end == wet.count { return index }
                    index = end
                } else {
                    index += 1
                }
            }
            return nil
        }

        var summary: NextHourSummary
        if wet.count >= 1, wet.prefix(minRun).allSatisfy({ $0 }) {
            // Precipitating now.
            let stop = firstRun(of: false, from: 1)
            let segment = Array(window[0..<(stop ?? window.count)])
            let phrase = precipitationPhrase(for: segment)
            if let stop {
                let stopsIn = offset(stop)
                var text = "\(phrase.capitalizedFirst) stopping in \(minutesText(stopsIn, coarse: coarse))"
                if let restart = firstRun(of: true, from: stop) {
                    let gap = window[restart].date.timeIntervalSince(window[stop].date)
                    text += ", starting again \(minutesText(gap, coarse: coarse)) later"
                }
                summary = NextHourSummary(
                    state: .stopping, text: text + ".",
                    shortText: "\(phrase.kind.noun.capitalizedFirst) ending in \(minutesText(stopsIn, coarse: coarse, approximate: false))",
                    startsIn: 0, endsIn: stopsIn, intensity: phrase.intensity, precipitationKind: phrase.kind,
                    isPossibleOnly: phrase.possible)
            } else {
                summary = NextHourSummary(
                    state: .continuing, text: "\(phrase.capitalizedFirst) for the hour.",
                    shortText: "\(phrase.kind.noun.capitalizedFirst) for the hour",
                    startsIn: 0, endsIn: nil, intensity: phrase.intensity, precipitationKind: phrase.kind,
                    isPossibleOnly: phrase.possible)
            }
        } else if let start = firstRun(of: true, from: 0) {
            let stop = firstRun(of: false, from: start + 1)
            let segment = Array(window[start..<(stop ?? window.count)])
            let phrase = precipitationPhrase(for: segment)
            let startsIn = max(coarse ? 0 : 60, offset(start))
            var text = "\(phrase.capitalizedFirst) starting in \(minutesText(startsIn, coarse: coarse))"
            var endsIn: TimeInterval?
            if let stop {
                let duration = window[stop].date.timeIntervalSince(window[start].date)
                endsIn = offset(stop)
                text += ", stopping \(minutesText(duration, coarse: coarse)) later"
            }
            summary = NextHourSummary(
                state: .starting, text: text + ".",
                shortText: "\(phrase.kind.noun.capitalizedFirst) in \(minutesText(startsIn, coarse: coarse, approximate: false))",
                startsIn: startsIn, endsIn: endsIn, intensity: phrase.intensity, precipitationKind: phrase.kind,
                isPossibleOnly: phrase.possible)
        } else {
            summary = NextHourSummary(
                state: .dry, text: "No precipitation expected for the next hour.",
                shortText: "Dry for the next hour", startsIn: nil, endsIn: nil,
                intensity: .none, precipitationKind: .none, isPossibleOnly: false)
        }

        if preferProviderText, let provided = forecast.providerSummary, !provided.isEmpty {
            summary.text = provided.hasSuffix(".") ? provided : provided + "."
        }
        return summary
    }

    static let unavailable = NextHourSummary(
        state: .unavailable, text: "Next-hour forecast unavailable.", shortText: "No minute data",
        startsIn: nil, endsIn: nil, intensity: .none, precipitationKind: .none, isPossibleOnly: false)

    static func isWet(_ sample: MinutePrecipitation) -> Bool {
        guard PrecipitationIntensity(millimetersPerHour: sample.intensity) > .none else { return false }
        return (sample.chance ?? 1) >= possibleChance
    }

    struct Phrase {
        var intensity: PrecipitationIntensity
        var kind: PrecipitationKind
        var possible: Bool

        var capitalizedFirst: String {
            var words: [String] = []
            if possible { words.append("possible") }
            if let adjective = intensity.adjective { words.append(adjective) }
            words.append(kind.noun)
            return words.joined(separator: " ").capitalizedFirst
        }
    }

    static func precipitationPhrase(for segment: [MinutePrecipitation]) -> Phrase {
        let wetSamples = segment.filter(isWet)
        let peak = wetSamples.map(\.intensity).max() ?? 0
        var counts: [PrecipitationKind: Int] = [:]
        for sample in wetSamples where sample.kind != .none { counts[sample.kind, default: 0] += 1 }
        let kind = counts.max { $0.value < $1.value }?.key ?? .rain
        let maxChance = wetSamples.compactMap(\.chance).max()
        let possible = maxChance.map { $0 < likelyChance } ?? false
        return Phrase(intensity: max(.veryLight, PrecipitationIntensity(millimetersPerHour: peak)), kind: kind, possible: possible)
    }

    /// "12 min" (minute data) or "about 15 min" (15-minute data).
    static func minutesText(_ interval: TimeInterval, coarse: Bool, approximate: Bool = true) -> String {
        var minutes = Int((interval / 60).rounded())
        if coarse {
            minutes = max(5, Int((Double(minutes) / 5).rounded()) * 5)
            return approximate ? "about \(minutes) min" : "~\(minutes) min"
        }
        return "\(max(1, minutes)) min"
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
