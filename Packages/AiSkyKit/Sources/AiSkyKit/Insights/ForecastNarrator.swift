import Foundation

/// Dark Sky style one-line summaries for the next 24 hours and the coming week.
public enum ForecastNarrator {
    /// e.g. "Light rain from 2 PM to 6 PM." or "Partly cloudy until 3 PM, then clear."
    public static func daySummary(
        hours allHours: [HourlyForecast],
        now: Date = Date(),
        timeZone: TimeZone,
        formatter: WeatherFormatter
    ) -> String {
        let hours = Array(allHours.filter { $0.date > now.addingTimeInterval(-3600) }.prefix(24))
        guard !hours.isEmpty else { return "" }

        var sentence: String
        let wet = hours.map(isWet)
        if let firstWet = wet.firstIndex(of: true) {
            let lastWet = wet.lastIndex(of: true)!
            let wetHours = hours.enumerated().filter { wet[$0.offset] }.map(\.element)
            let phrase = precipitationPhrase(for: wetHours)
            let wetCount = wet.filter { $0 }.count
            let startsNow = firstWet == 0
            let lastsToEnd = lastWet >= hours.count - 1
            let startTime = formatter.hour(hours[firstWet].date, timeZone: timeZone)
            let endTime = formatter.hour(hours[lastWet].date.addingTimeInterval(3600), timeZone: timeZone)

            if startsNow && lastsToEnd && wetCount >= hours.count * 3 / 4 {
                sentence = "\(phrase) throughout the day"
            } else if startsNow {
                sentence = "\(phrase) until \(endTime)"
            } else if lastsToEnd {
                sentence = "\(phrase) starting around \(startTime)"
            } else if lastWet == firstWet {
                sentence = "\(phrase) possible around \(startTime)"
            } else {
                sentence = "\(phrase) from \(startTime) to \(endTime)"
            }
            if wetCount < (lastWet - firstWet + 1) / 2 {
                sentence = sentence.replacingOccurrences(of: phrase, with: "On and off \(phrase.lowercasedFirst)")
            }
        } else {
            sentence = skySummary(hours: hours, timeZone: timeZone, formatter: formatter)
        }

        var result = sentence + "."
        if let gust = hours.compactMap(\.windGust).max(), gust >= 50 {
            result += " Gusts up to \(formatter.windSpeed(gust))."
        }
        return result
    }

    /// e.g. "Rain on Tuesday and Thursday, with high temperatures peaking at 84° on Saturday."
    public static func weekSummary(
        days allDays: [DailyForecast],
        now: Date = Date(),
        timeZone: TimeZone,
        formatter: WeatherFormatter
    ) -> String {
        let days = Array(allDays.prefix(7))
        guard days.count >= 2 else { return "" }

        let wetDays = days.enumerated().filter { ($0.element.precipitationChance ?? 0) >= 0.5 || ($0.element.precipitationAmount ?? 0) >= 2.5 }
        var counts: [PrecipitationKind: Int] = [:]
        for (_, day) in wetDays {
            let kind = day.precipitationKind == .none ? day.condition.precipitationKind : day.precipitationKind
            counts[kind == .none ? .rain : kind, default: 0] += 1
        }
        let kind = counts.max { $0.value < $1.value }?.key ?? .rain
        let noun = kind == .mixed ? "Wintry mix" : kind.noun.capitalizedFirst

        func name(_ index: Int) -> String {
            switch index {
            case 0: return "today"
            case 1: return "tomorrow"
            default: return formatter.weekday(days[index].date, timeZone: timeZone)
            }
        }

        var precipitationPart: String
        let indices = wetDays.map(\.offset)
        switch indices.count {
        case 0:
            precipitationPart = "No precipitation throughout the week"
        case 1:
            precipitationPart = "\(noun) \(indices[0] <= 1 ? name(indices[0]) : "on " + name(indices[0]))"
        case 2:
            precipitationPart = "\(noun) \(joinDays(indices.map(name)))"
        default:
            let consecutive = indices.last! - indices.first! == indices.count - 1
            if indices.count >= days.count - 1 {
                precipitationPart = "\(noun) most of the week"
            } else if consecutive {
                precipitationPart = "\(noun) \(name(indices.first!)) through \(name(indices.last!))"
            } else {
                precipitationPart = "\(noun) \(joinDays(indices.map(name)))"
            }
        }
        precipitationPart = precipitationPart.replacingOccurrences(of: " on today", with: " today")
            .replacingOccurrences(of: " on tomorrow", with: " tomorrow")

        let highs = days.map(\.high)
        let maxIndex = highs.indices.max { highs[$0] < highs[$1] }!
        let minIndex = highs.indices.min { highs[$0] < highs[$1] }!
        let temperaturePart: String
        if maxIndex > 0 || minIndex == 0 {
            temperaturePart = "high temperatures peaking at \(formatter.temperature(highs[maxIndex])) \(dayPhrase(maxIndex, name: name))"
        } else {
            temperaturePart = "high temperatures bottoming out at \(formatter.temperature(highs[minIndex])) \(dayPhrase(minIndex, name: name))"
        }
        return "\(precipitationPart), with \(temperaturePart)."
    }

    // MARK: Helpers

    static func isWet(_ hour: HourlyForecast) -> Bool {
        if let chance = hour.precipitationChance {
            return chance >= 0.5 && ((hour.precipitationAmount ?? 0.2) >= 0.1 || hour.condition.isPrecipitation)
        }
        return (hour.precipitationAmount ?? 0) >= 0.2
    }

    static func precipitationPhrase(for hours: [HourlyForecast]) -> String {
        let peak = hours.compactMap(\.precipitationAmount).max() ?? 1
        var counts: [PrecipitationKind: Int] = [:]
        for hour in hours {
            let kind = hour.precipitationKind != .none ? hour.precipitationKind : hour.condition.precipitationKind
            if kind != .none { counts[kind, default: 0] += 1 }
        }
        let kind = counts.max { $0.value < $1.value }?.key ?? .rain
        if hours.contains(where: { $0.condition.isThunderstorm }) && kind == .rain {
            return "Thunderstorms"
        }
        let intensity = max(.veryLight, PrecipitationIntensity(millimetersPerHour: peak))
        let words = [intensity.adjective, kind.noun].compactMap { $0 }
        return words.joined(separator: " ").capitalizedFirst
    }

    static func skyPhrase(_ family: ConditionFamily) -> String {
        switch family {
        case .clear: return "clear"
        case .partlyCloudy: return "partly cloudy"
        case .cloudy: return "mostly cloudy"
        case .fog: return "foggy"
        case .windy: return "windy"
        case .lightRain, .rain, .heavyRain, .storm: return "showery"
        case .sleet: return "icy"
        case .snow: return "snowy"
        }
    }

    static func skySummary(hours: [HourlyForecast], timeZone: TimeZone, formatter: WeatherFormatter) -> String {
        let families = hours.map { $0.condition.family }
        func mode(_ values: ArraySlice<ConditionFamily>) -> (family: ConditionFamily, count: Int) {
            var counts: [ConditionFamily: Int] = [:]
            for value in values { counts[value, default: 0] += 1 }
            let best = counts.max { $0.value < $1.value || ($0.value == $1.value && $0.key.rawValue > $1.key.rawValue) }!
            return (best.key, best.value)
        }

        // A lasting change: the first condition holds for 3+ hours, then something else
        // dominates the rest of the period.
        let first = families[0]
        let firstRun = families.prefix { $0 == first }.count
        if firstRun >= 3, firstRun <= families.count - 3 {
            let rest = mode(families[firstRun...])
            if rest.family != first, Double(rest.count) >= Double(families.count - firstRun) * 0.6 {
                let time = formatter.hour(hours[firstRun].date, timeZone: timeZone)
                return "\(skyPhrase(first).capitalizedFirst) until \(time), then \(skyPhrase(rest.family))"
            }
        }

        let dominant = mode(families[...])
        if dominant.count * 4 >= families.count * 3 {
            return "\(skyPhrase(dominant.family).capitalizedFirst) throughout the day"
        }
        return "\(skyPhrase(dominant.family).capitalizedFirst) for most of the day"
    }

    static func joinDays(_ names: [String]) -> String {
        let withOn = names.map { $0 == "today" || $0 == "tomorrow" ? $0 : "on \($0)" }
        switch withOn.count {
        case 0: return ""
        case 1: return withOn[0]
        case 2: return "\(withOn[0]) and \(withOn[1])"
        default: return withOn.dropLast().joined(separator: ", ") + ", and " + withOn.last!
        }
    }

    static func dayPhrase(_ index: Int, name: (Int) -> String) -> String {
        index <= 1 ? name(index) : "on \(name(index))"
    }
}

extension String {
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
