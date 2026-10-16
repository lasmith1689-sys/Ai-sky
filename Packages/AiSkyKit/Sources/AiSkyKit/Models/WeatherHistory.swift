import Foundation

/// One local day of weather from the Time Machine: past (observed-ish), today, or forecast.
public struct HistoricalDay: Codable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable {
        /// High-resolution weather models (the last three months, and forecasts).
        case forecastModels
        /// ERA5 / ECMWF reanalysis (older dates).
        case reanalysis
    }

    /// Local midnight.
    public var date: Date
    public var timeZoneIdentifier: String
    public var summary: DailyForecast?
    /// The day's hours, starting at local midnight.
    public var hours: [HourlyForecast]
    public var source: Source
    /// A future date, so the values are a forecast.
    public var isForecast: Bool
    public var isToday: Bool

    public init(
        date: Date,
        timeZoneIdentifier: String,
        summary: DailyForecast?,
        hours: [HourlyForecast],
        source: Source,
        isForecast: Bool,
        isToday: Bool = false
    ) {
        self.date = date
        self.timeZoneIdentifier = timeZoneIdentifier
        self.summary = summary
        self.hours = hours
        self.source = source
        self.isForecast = isForecast
        self.isToday = isToday
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    /// Total precipitation for the day, mm.
    public var precipitationTotal: Double? {
        if let amount = summary?.precipitationAmount { return amount }
        let amounts = hours.compactMap(\.precipitationAmount)
        return amounts.isEmpty ? nil : amounts.reduce(0, +)
    }

    /// Hottest and coldest hour (falls back to the daily summary).
    public var high: Double? { summary?.high ?? hours.map(\.temperature).max() }
    public var low: Double? { summary?.low ?? hours.map(\.temperature).min() }

    /// Where the numbers come from, for the footer.
    public var sourceDescription: String {
        switch source {
        case .forecastModels:
            return isForecast
                ? "Forecast from Open-Meteo weather models."
                : "Hourly values from Open-Meteo's weather-model analyses."
        case .reanalysis:
            return "Reconstructed from ERA5 and ECMWF reanalysis (Open-Meteo historical archive). Values are area averages, not a local weather station's readings."
        }
    }
}

/// Average precipitation for each calendar day over a climate period (1991–2020), so any date
/// range can be compared with normal, as Precip does.
public struct PrecipitationNormals: Codable, Sendable, Equatable {
    /// Mean daily precipitation (mm) for each calendar day in leap-year order (index 59 = Feb 29),
    /// smoothed with a two-week moving average.
    public var dailyMeans: [Double]
    public var firstYear: Int
    public var lastYear: Int

    public init(dailyMeans: [Double], firstYear: Int, lastYear: Int) {
        self.dailyMeans = dailyMeans
        self.firstYear = firstYear
        self.lastYear = lastYear
    }

    private static let daysBeforeMonth = [0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335]
    private static let daysInMonth = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

    /// Position of a calendar day in leap-year order (0...365).
    public static func index(month: Int, day: Int) -> Int? {
        guard (1...12).contains(month), day >= 1, day <= daysInMonth[month - 1] else { return nil }
        return daysBeforeMonth[month - 1] + day - 1
    }

    /// Normal precipitation for the calendar day of `date`, mm.
    public func mean(on date: Date, calendar: Calendar) -> Double {
        let parts = calendar.dateComponents([.month, .day], from: date)
        guard let month = parts.month, let day = parts.day,
              let index = Self.index(month: month, day: day), dailyMeans.indices.contains(index) else {
            return 0
        }
        return dailyMeans[index]
    }

    /// Normal total for the local days `start...end` (inclusive), mm.
    public func total(from start: Date, to end: Date, calendar: Calendar) -> Double {
        var sum = 0.0
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while day <= last {
            sum += mean(on: day, calendar: calendar)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return sum
    }

    /// Normal for a whole year, mm.
    public var annualTotal: Double {
        // A non-leap year: every calendar day except February 29.
        dailyMeans.enumerated().reduce(0) { $1.offset == 59 ? $0 : $0 + $1.element }
    }

    /// Builds normals from daily totals (local midnights) spanning several years.
    public static func compute(
        from samples: [PrecipitationSample],
        calendar: Calendar,
        years: ClosedRange<Int>? = nil,
        smoothingRadius: Int = 7
    ) -> PrecipitationNormals? {
        var sums = [Double](repeating: 0, count: 366)
        var counts = [Int](repeating: 0, count: 366)
        var firstYear = Int.max
        var lastYear = Int.min
        for sample in samples {
            let parts = calendar.dateComponents([.year, .month, .day], from: sample.date)
            guard let year = parts.year, let month = parts.month, let day = parts.day,
                  years?.contains(year) ?? true,
                  let index = index(month: month, day: day) else {
                continue
            }
            sums[index] += sample.amount
            counts[index] += 1
            firstYear = min(firstYear, year)
            lastYear = max(lastYear, year)
        }
        // Require most of the calendar and at least a few years of data.
        guard counts.filter({ $0 > 0 }).count >= 300, lastYear - firstYear >= 2 else { return nil }

        let raw: [Double?] = (0..<366).map { counts[$0] > 0 ? sums[$0] / Double(counts[$0]) : nil }
        let smoothed: [Double] = (0..<366).map { index in
            var total = 0.0
            var count = 0
            for offset in -smoothingRadius...smoothingRadius {
                if let value = raw[(index + offset + 366) % 366] {
                    total += value
                    count += 1
                }
            }
            return count > 0 ? total / Double(count) : 0
        }
        return PrecipitationNormals(dailyMeans: smoothed, firstYear: firstYear, lastYear: lastYear)
    }
}
