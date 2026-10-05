import Foundation

/// Time spans on the rainfall history screen: Precip's week … year presets, or any range.
public enum RainfallPeriod: Hashable, Sendable {
    case last7Days
    case last30Days
    case monthToDate
    case yearToDate
    case last12Months
    case custom(start: Date, end: Date)

    public static let presets: [RainfallPeriod] = [.last7Days, .last30Days, .monthToDate, .yearToDate, .last12Months]

    public var title: String {
        switch self {
        case .last7Days: return "7 Days"
        case .last30Days: return "30 Days"
        case .monthToDate: return "Month"
        case .yearToDate: return "Year"
        case .last12Months: return "12 Mo"
        case .custom: return "Custom"
        }
    }

    /// Local midnights of the first and last day, inclusive. Presets end today.
    public func dateRange(today: Date, calendar: Calendar) -> ClosedRange<Date> {
        let today = calendar.startOfDay(for: today)
        func daysAgo(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: today) ?? today
        }
        switch self {
        case .last7Days:
            return daysAgo(6)...today
        case .last30Days:
            return daysAgo(29)...today
        case .monthToDate:
            return (calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today)...today
        case .yearToDate:
            return (calendar.date(from: calendar.dateComponents([.year], from: today)) ?? today)...today
        case .last12Months:
            let yearAgo = calendar.date(byAdding: .year, value: -1, to: today) ?? today
            return (calendar.date(byAdding: .day, value: 1, to: yearAgo) ?? yearAgo)...today
        case .custom(let start, let end):
            let first = calendar.startOfDay(for: min(start, end))
            let last = min(calendar.startOfDay(for: max(start, end)), today)
            return min(first, last)...last
        }
    }
}

/// How the history chart groups days.
public enum RainfallGranularity: String, Sendable {
    case day, week, month, year

    /// Daily bars for about two months, weekly up to five, then monthly, then yearly.
    public static func automatic(forDays days: Int) -> RainfallGranularity {
        switch days {
        case ...62: return .day
        case ...150: return .week
        case ...1100: return .month
        default: return .year
        }
    }
}

/// Daily precipitation totals for one place, with optional climate normals, and the Precip-style
/// statistics derived from them.
public struct RainfallRecord: Sendable, Equatable {
    /// Days with at least 0.01 in (0.254 mm) count as wet: the NWS "measurable precipitation".
    public static let measurable = 0.254

    public private(set) var days: [Date: PrecipitationSample]
    public var normals: PrecipitationNormals?
    public let calendar: Calendar

    public init(samples: [PrecipitationSample] = [], normals: PrecipitationNormals? = nil, calendar: Calendar) {
        self.days = [:]
        self.normals = normals
        self.calendar = calendar
        merge(samples)
    }

    /// Adds or replaces daily totals.
    public mutating func merge(_ samples: [PrecipitationSample]) {
        for sample in samples {
            let key = dayKey(sample.date)
            var normalized = sample
            normalized.date = key
            days[key] = normalized
        }
    }

    /// The local day a sample stamped at (roughly) local midnight belongs to. Looking at the
    /// following noon tolerates a data source whose time zone is off by a few hours.
    public func dayKey(_ date: Date) -> Date {
        calendar.startOfDay(for: date.addingTimeInterval(12 * 3600))
    }

    /// Local midnights for every day in `range`.
    public func eachDay(in range: ClosedRange<Date>) -> [Date] {
        var result: [Date] = []
        var day = calendar.startOfDay(for: range.lowerBound)
        let last = calendar.startOfDay(for: range.upperBound)
        while day <= last {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// Days in `range` without data.
    public func missingDays(in range: ClosedRange<Date>) -> [Date] {
        eachDay(in: range).filter { days[$0] == nil }
    }

    // MARK: Summary

    public struct Summary: Sendable, Equatable {
        public var range: ClosedRange<Date>
        public var dayCount: Int
        /// Days without data (e.g. still being processed).
        public var missingDays: Int
        /// mm
        public var total: Double
        /// cm
        public var snowfall: Double
        public var wetDays: Int
        public var wettestDay: PrecipitationSample?
        /// Longest run of consecutive days without measurable precipitation.
        public var longestDrySpell: Int
        /// 1991–2020 average for the same calendar days, mm.
        public var normal: Double?
        /// The same days one year earlier, mm (when fully known).
        public var lastYear: Double?

        /// 1.0 = exactly normal.
        public var fractionOfNormal: Double? {
            guard let normal, normal >= 0.5 else { return nil }
            return total / normal
        }

        public var departureFromNormal: Double? {
            normal.map { total - $0 }
        }
    }

    public func summary(for range: ClosedRange<Date>) -> Summary {
        let dates = eachDay(in: range)
        let samples = dates.compactMap { days[$0] }
        var longestDry = 0
        var currentDry = 0
        for date in dates {
            if let sample = days[date], sample.amount >= Self.measurable {
                currentDry = 0
            } else if days[date] != nil {
                currentDry += 1
                longestDry = max(longestDry, currentDry)
            }
        }
        return Summary(
            range: range,
            dayCount: dates.count,
            missingDays: dates.count - samples.count,
            total: samples.reduce(0) { $0 + $1.amount },
            snowfall: samples.reduce(0) { $0 + ($1.snowfall ?? 0) },
            wetDays: samples.filter { $0.amount >= Self.measurable }.count,
            wettestDay: samples.filter { $0.amount >= Self.measurable }.max { $0.amount < $1.amount },
            longestDrySpell: longestDry,
            normal: normals?.total(from: range.lowerBound, to: range.upperBound, calendar: calendar),
            lastYear: total(yearsBefore: 1, range: range)
        )
    }

    /// Total for `range` shifted back by whole years, or `nil` unless every day is known.
    public func total(yearsBefore years: Int, range: ClosedRange<Date>) -> Double? {
        guard let start = calendar.date(byAdding: .year, value: -years, to: range.lowerBound),
              let end = calendar.date(byAdding: .year, value: -years, to: range.upperBound) else {
            return nil
        }
        var sum = 0.0
        for date in eachDay(in: start...end) {
            guard let sample = days[date] else { return nil }
            sum += sample.amount
        }
        return sum
    }

    // MARK: Chart data

    public struct Bar: Sendable, Equatable, Identifiable {
        public var id: Date { start }
        /// Local midnight of the first day in the bar.
        public var start: Date
        /// Local midnight of the last day in the bar (inclusive, clipped to the range).
        public var end: Date
        /// mm
        public var amount: Double
        /// Normal for the same days, mm.
        public var normal: Double?
        /// Some days of the bar have no data yet.
        public var isIncomplete: Bool
    }

    public func bars(for range: ClosedRange<Date>, granularity: RainfallGranularity? = nil) -> (RainfallGranularity, [Bar]) {
        let dates = eachDay(in: range)
        let granularity = granularity ?? .automatic(forDays: dates.count)
        var groups: [(start: Date, dates: [Date])] = []
        for date in dates {
            let start = groupStart(of: date, granularity: granularity)
            if let last = groups.last, last.start == start {
                groups[groups.count - 1].dates.append(date)
            } else {
                groups.append((start, [date]))
            }
        }
        let bars = groups.map { group -> Bar in
            let samples = group.dates.compactMap { days[$0] }
            let first = group.dates.first ?? group.start
            let last = group.dates.last ?? group.start
            return Bar(
                start: first,
                end: last,
                amount: samples.reduce(0) { $0 + $1.amount },
                normal: normals?.total(from: first, to: last, calendar: calendar),
                isIncomplete: samples.count < group.dates.count
            )
        }
        return (granularity, bars)
    }

    private func groupStart(of date: Date, granularity: RainfallGranularity) -> Date {
        switch granularity {
        case .day:
            return date
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        case .month:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        case .year:
            return calendar.date(from: calendar.dateComponents([.year], from: date)) ?? date
        }
    }

    public struct CumulativePoint: Sendable, Equatable, Identifiable {
        public var id: Date { date }
        /// Local midnight; the total includes this day.
        public var date: Date
        public var total: Double
        public var normal: Double?
    }

    /// Running totals across `range` (Precip's "this year vs. normal" curve).
    public func cumulative(for range: ClosedRange<Date>) -> [CumulativePoint] {
        var total = 0.0
        var normal = 0.0
        return eachDay(in: range).map { date in
            total += days[date]?.amount ?? 0
            if let normals {
                normal += normals.mean(on: date, calendar: calendar)
            }
            return CumulativePoint(date: date, total: total, normal: normals == nil ? nil : normal)
        }
    }
}
