import Foundation

/// The next hour's precipitation reduced to what the looks put into words: what falls, how hard,
/// and when it starts and stops. Each look phrases it in its own voice from the same data.
public struct NextHourWindow: Equatable, Sendable {
    public var state: NextHourSummary.State
    /// What falls (rain when the provider didn't say).
    public var kind: PrecipitationKind
    public var intensity: PrecipitationIntensity
    /// When precipitation starts (nil when it already has, or none is expected).
    public var start: Date?
    /// When it stops (nil when it lasts past the hour or none is expected).
    public var end: Date?
    public var startsInMinutes: Int?
    public var endsInMinutes: Int?
    /// 15-minute data: times are approximate.
    public var isApproximate: Bool

    public init(summary: NextHourSummary, now: Date, isApproximate: Bool = false) {
        state = summary.state
        kind = summary.precipitationKind == .none ? .rain : summary.precipitationKind
        intensity = summary.intensity
        self.isApproximate = isApproximate
        switch summary.state {
        case .starting:
            let startsIn = summary.startsIn ?? 0
            start = now.addingTimeInterval(startsIn)
            startsInMinutes = max(1, Int((startsIn / 60).rounded()))
        case .stopping, .continuing, .dry, .unavailable:
            start = nil
            startsInMinutes = nil
        }
        if let endsIn = summary.endsIn, summary.state == .starting || summary.state == .stopping {
            end = now.addingTimeInterval(endsIn)
            endsInMinutes = max(1, Int((endsIn / 60).rounded()))
        } else {
            end = nil
            endsInMinutes = nil
        }
    }

    public init(forecast: NextHourForecast?, now: Date) {
        self.init(
            summary: NextHourSummarizer.summarize(forecast, now: now, preferProviderText: false),
            now: now,
            isApproximate: (forecast?.resolution ?? 60) > 120
        )
    }

    public var isPrecipitating: Bool {
        state == .starting || state == .stopping || state == .continuing
    }

    /// "rain", "snow", "wintry mix".
    public var noun: String { kind.noun }

    /// "light rain", "rain", "heavy snow" (very light reads as light).
    public var phrase: String {
        switch intensity {
        case .veryLight, .light: return "light \(noun)"
        case .heavy: return "heavy \(noun)"
        case .none, .moderate: return noun
        }
    }

    /// "Light", "Moderate", "Heavy" for a one-word badge; nil when dry.
    public var intensityWord: String? {
        guard isPrecipitating else { return nil }
        switch intensity {
        case .none, .veryLight, .light: return "Light"
        case .moderate: return "Moderate"
        case .heavy: return "Heavy"
        }
    }

    private var about: String { isApproximate ? "about " : "" }

    private func minutes(_ value: Int, short: Bool) -> String {
        short ? "\(value) min" : (value == 1 ? "1 minute" : "\(value) minutes")
    }

    // MARK: Phrasings

    /// Instrument's card header: "RAIN 15:30 → 16:10", "RAIN NOW → 16:10", "RAIN FROM 15:30".
    public func instrumentHeader(clock: (Date) -> String) -> String {
        let noun = self.noun.uppercased()
        switch state {
        case .unavailable: return "NO MINUTE DATA"
        case .dry: return "NO RAIN"
        case .continuing: return "\(noun) ALL HOUR"
        case .stopping: return end.map { "\(noun) NOW → \(clock($0))" } ?? "\(noun) NOW"
        case .starting:
            let from = start.map(clock) ?? ""
            if let end { return "\(noun) \(from) → \(clock(end))" }
            return "\(noun) FROM \(from)"
        }
    }

    /// Obsidian's label: "LIGHT RAIN 15:30 TO 16:10".
    public func obsidianHeader(clock: (Date) -> String) -> String {
        let phrase = self.phrase.uppercased()
        switch state {
        case .unavailable: return "NO MINUTE DATA"
        case .dry: return "DRY"
        case .continuing: return "\(phrase) ALL HOUR"
        case .stopping: return end.map { "\(phrase) UNTIL \(clock($0))" } ?? phrase
        case .starting:
            let from = start.map(clock) ?? ""
            if let end { return "\(phrase) \(from) TO \(clock(end))" }
            return "\(phrase) FROM \(from)"
        }
    }

    /// A short sentence under a hero: "Rain in 18 min, gone by 4:10." Nil when dry.
    public func sentence(clock: (Date) -> String) -> String? {
        let noun = self.noun.capitalizedFirst
        switch state {
        case .unavailable, .dry: return nil
        case .continuing: return "\(noun) for the next hour."
        case .stopping:
            if let end, let minutes = endsInMinutes {
                return "\(noun) ending in \(about)\(self.minutes(minutes, short: true)), around \(clock(end))."
            }
            return "\(noun) ending soon."
        case .starting:
            let wait = startsInMinutes.map { "in \(about)\(self.minutes($0, short: true))" } ?? "soon"
            if let end { return "\(noun) \(wait), gone by \(clock(end))." }
            return "\(noun) \(wait)."
        }
    }

    /// Compact status: "Rain in 18 min", "Rain ending in 20 min", "Rain for the hour". Nil when dry.
    public func status(long: Bool = false) -> String? {
        let noun = self.noun.capitalizedFirst
        switch state {
        case .unavailable, .dry: return nil
        case .continuing: return "\(noun) for the hour"
        case .stopping:
            return endsInMinutes.map { "\(noun) ending in \(about)\(minutes($0, short: !long))" } ?? "\(noun) ending soon"
        case .starting:
            return startsInMinutes.map { "\(noun) in \(about)\(minutes($0, short: !long))" } ?? "\(noun) soon"
        }
    }

    /// Liquid's card title: "Light rain in 18 min".
    public var liquidTitle: String {
        switch state {
        case .unavailable: return "No minute data"
        case .dry: return "No rain for the next hour"
        case .continuing: return "\(phrase.capitalizedFirst) for the hour"
        case .stopping: return endsInMinutes.map { "\(phrase.capitalizedFirst) ending in \(about)\($0) min" } ?? phrase.capitalizedFirst
        case .starting: return startsInMinutes.map { "\(phrase.capitalizedFirst) in \(about)\($0) min" } ?? phrase.capitalizedFirst
        }
    }

    /// Liquid's card detail: "until about 4:10".
    public func liquidDetail(clock: (Date) -> String) -> String? {
        guard let end, state == .starting || state == .stopping else { return nil }
        return "until about \(clock(end))"
    }

    /// Editorial's italic note: "Light rain, 3:30 to 4:10".
    public func editorialNote(clock: (Date) -> String) -> String {
        let phrase = self.phrase.capitalizedFirst
        switch state {
        case .unavailable: return "No minute data"
        case .dry: return "Dry for the hour"
        case .continuing: return "\(phrase) all hour"
        case .stopping: return end.map { "\(phrase) until \(clock($0))" } ?? phrase
        case .starting:
            let from = start.map(clock) ?? ""
            if let end { return "\(phrase), \(from) to \(clock(end))" }
            return "\(phrase) from \(from)"
        }
    }

    /// Chroma's next-hour block: "Rain at 3:30, done by 4:10".
    public func chromaTitle(clock: (Date) -> String) -> String {
        let noun = self.noun.capitalizedFirst
        switch state {
        case .unavailable: return "No minute-by-minute data"
        case .dry: return "Dry for the next hour"
        case .continuing: return "\(noun) all hour"
        case .stopping: return end.map { "\(noun) now, done by \(clock($0))" } ?? "\(noun) now"
        case .starting:
            let at = start.map(clock) ?? ""
            if let end { return "\(noun) at \(at), done by \(clock(end))" }
            return "\(noun) from \(at)"
        }
    }
}

/// Editorial's headline: the next hour or the day, written as a newspaper sentence.
/// "Rain arrives in eighteen minutes and is gone by ten past four."
public enum EditorialHeadline {
    public static func sentence(window: NextHourWindow, timeZone: TimeZone, fallback: String) -> String {
        var noun = window.noun.capitalizedFirst
        if window.intensity == .heavy { noun = "Heavy \(window.noun)" }
        let about = window.isApproximate ? "about " : ""
        switch window.state {
        case .starting:
            let wait = window.startsInMinutes.map { "in \(about)\(minutesWords($0))" } ?? "soon"
            if let end = window.end {
                return "\(noun) arrives \(wait) and is gone by \(ClockWords.phrase(end, timeZone: timeZone))."
            }
            return "\(noun) arrives \(wait) and lasts the rest of the hour."
        case .stopping:
            if let end = window.end {
                return "\(noun) until about \(ClockWords.phrase(end, timeZone: timeZone)), then drying out."
            }
            return "\(noun) easing off soon."
        case .continuing:
            return "\(noun) for the next hour at least."
        case .dry, .unavailable:
            return fallback
        }
    }

    /// "eighteen minutes", "a minute".
    static func minutesWords(_ minutes: Int) -> String {
        minutes <= 1 ? "a minute" : "\(ClockWords.spell(minutes)) minutes"
    }
}

/// Times as people say them: "ten past four", "half past six", "quarter to nine", "noon".
public enum ClockWords {
    public static func phrase(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var hour = calendar.component(.hour, from: date)
        var minute = Int((Double(calendar.component(.minute, from: date)) / 5).rounded()) * 5
        if minute == 60 {
            minute = 0
            hour = (hour + 1) % 24
        }
        let next = (hour + 1) % 24
        switch minute {
        case 0:
            if hour == 12 { return "noon" }
            if hour == 0 { return "midnight" }
            return "\(hourWord(hour)) o'clock"
        case 15: return "quarter past \(hourWord(hour))"
        case 30: return "half past \(hourWord(hour))"
        case 45: return "quarter to \(hourWord(next))"
        case ..<30: return "\(spell(minute)) past \(hourWord(hour))"
        default: return "\(spell(60 - minute)) to \(hourWord(next))"
        }
    }

    /// "four" for 4 or 16; "twelve" for noon and midnight.
    static func hourWord(_ hour: Int) -> String {
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return spell(twelve)
    }

    static func spell(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .spellOut
        return formatter.string(from: NSNumber(value: number)) ?? String(number)
    }
}
