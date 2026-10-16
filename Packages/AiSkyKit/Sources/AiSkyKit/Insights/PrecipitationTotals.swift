import Foundation

/// Precip-style rainfall accounting: how much fell recently and how much is coming.
public struct PrecipitationTotals: Sendable, Equatable {
    public struct Bar: Sendable, Equatable, Identifiable {
        public var id: Date { date }
        /// Local midnight.
        public var date: Date
        /// Observed (analyzed) precipitation, mm.
        public var observed: Double
        /// Forecast precipitation still to come, mm.
        public var forecast: Double
        public var isToday: Bool

        public var total: Double { observed + forecast }
    }

    public struct LastPrecipitation: Sendable, Equatable {
        /// End of the most recent hour with measurable precipitation.
        public var date: Date
        /// Total for that local day, mm.
        public var dayTotal: Double
    }

    // Past (mm)
    public var pastHour: Double?
    public var past24Hours: Double?
    public var past48Hours: Double?
    public var past7Days: Double?
    public var past30Days: Double?
    public var todaySoFar: Double?
    // Snow (cm)
    public var snowPast24Hours: Double?
    public var snowPast7Days: Double?
    // Upcoming (mm)
    public var nextHour: Double?
    public var next24Hours: Double?
    public var next7Days: Double?
    public var snowNext24Hours: Double?

    public var lastPrecipitation: LastPrecipitation?
    /// Past 14 days, today, and the next 6 days.
    public var dailyBars: [Bar]

    /// Anything measurable (≥ 0.1 mm / 0.1 cm) falling in this snapshot's window?
    public var hasAnyPrecipitation: Bool {
        [past7Days, next7Days, snowPast7Days].compactMap { $0 }.contains { $0 >= 0.1 }
    }

    public static func compute(for snapshot: WeatherSnapshot, now: Date = Date()) -> PrecipitationTotals {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot.timeZone
        let today = calendar.startOfDay(for: now)
        let hourlyHistory = snapshot.precipitationHistory?.hourly ?? []
        let dailyHistory = snapshot.precipitationHistory?.daily ?? []

        /// Sum of completed history hours that ended within the last `interval` seconds.
        func pastSum(_ interval: TimeInterval, _ value: (PrecipitationSample) -> Double?) -> Double {
            hourlyHistory
                .filter {
                    let end = $0.date.addingTimeInterval(3600)
                    return end > now.addingTimeInterval(-interval) && end <= now.addingTimeInterval(60)
                }
                .reduce(0) { $0 + (value($1) ?? 0) }
        }

        var totals = PrecipitationTotals(dailyBars: [])
        if !hourlyHistory.isEmpty {
            totals.pastHour = pastSum(3600) { $0.amount }
            totals.past24Hours = pastSum(24 * 3600) { $0.amount }
            totals.past48Hours = pastSum(48 * 3600) { $0.amount }
            totals.past7Days = pastSum(7 * 24 * 3600) { $0.amount }
            totals.snowPast24Hours = pastSum(24 * 3600) { $0.snowfall }
            totals.snowPast7Days = pastSum(7 * 24 * 3600) { $0.snowfall }
            totals.todaySoFar = hourlyHistory
                .filter { $0.date >= today && $0.date.addingTimeInterval(3600) <= now.addingTimeInterval(60) }
                .reduce(0) { $0 + $1.amount }
        }
        if !dailyHistory.isEmpty {
            let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            let fullDays = dailyHistory.filter { $0.date >= start && $0.date < today }.reduce(0) { $0 + $1.amount }
            totals.past30Days = fullDays + (totals.todaySoFar ?? 0)
        }

        // Upcoming
        let upcomingHours = snapshot.hourly.filter { $0.date.addingTimeInterval(3600) > now }
        func futureSum(_ interval: TimeInterval, _ value: (HourlyForecast) -> Double?) -> Double? {
            let end = now.addingTimeInterval(interval)
            let hours = upcomingHours.filter { $0.date < end }
            guard !hours.isEmpty else { return nil }
            return hours.reduce(0) { sum, hour in
                // Count only the part of the hour that is still ahead.
                let start = max(hour.date, now)
                let finish = min(hour.date.addingTimeInterval(3600), end)
                let fraction = max(0, finish.timeIntervalSince(start)) / 3600
                return sum + (value(hour) ?? 0) * fraction
            }
        }
        if let nextHour = snapshot.nextHour {
            let window = nextHour.window(from: now, duration: 3600)
            if !window.isEmpty {
                totals.nextHour = window.reduce(0) { sum, sample in
                    let start = max(sample.date, now)
                    let end = min(sample.date.addingTimeInterval(nextHour.resolution), now.addingTimeInterval(3600))
                    return sum + sample.intensity * max(0, end.timeIntervalSince(start)) / 3600
                }
            }
        }
        if totals.nextHour == nil {
            totals.nextHour = futureSum(3600) { $0.precipitationAmount }
        }
        totals.next24Hours = futureSum(24 * 3600) { $0.precipitationAmount }
        totals.snowNext24Hours = futureSum(24 * 3600) { $0.snowfallAmount }

        let restOfToday: Double = {
            let midnight = calendar.date(byAdding: .day, value: 1, to: today) ?? now
            return futureSum(midnight.timeIntervalSince(now)) { $0.precipitationAmount } ?? 0
        }()
        let comingDays = snapshot.daily.filter { $0.date > today.addingTimeInterval(3600) }.prefix(6)
        if !snapshot.daily.isEmpty || !upcomingHours.isEmpty {
            totals.next7Days = restOfToday + comingDays.reduce(0) { $0 + ($1.precipitationAmount ?? 0) }
        }

        // Most recent measurable precipitation.
        if let last = hourlyHistory.last(where: { $0.amount >= 0.1 && $0.date < now }) {
            let day = calendar.startOfDay(for: last.date)
            let dayTotal: Double
            if day == today {
                dayTotal = totals.todaySoFar ?? last.amount
            } else if let daily = dailyHistory.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
                dayTotal = daily.amount
            } else {
                dayTotal = hourlyHistory.filter { calendar.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.amount }
            }
            totals.lastPrecipitation = LastPrecipitation(date: last.date.addingTimeInterval(3600), dayTotal: dayTotal)
        } else if let lastDay = dailyHistory.last(where: { $0.amount >= 0.1 && $0.date < today }) {
            let end = calendar.date(byAdding: .day, value: 1, to: lastDay.date) ?? lastDay.date
            totals.lastPrecipitation = LastPrecipitation(date: end, dayTotal: lastDay.amount)
        }

        // Daily bars: 14 past days, today (observed + remaining forecast), next 6 days.
        var bars: [Bar] = []
        let pastStart = calendar.date(byAdding: .day, value: -14, to: today) ?? today
        for sample in dailyHistory where sample.date >= pastStart && sample.date < today {
            bars.append(Bar(date: sample.date, observed: sample.amount, forecast: 0, isToday: false))
        }
        bars.append(Bar(date: today, observed: totals.todaySoFar ?? 0, forecast: restOfToday, isToday: true))
        for day in comingDays {
            bars.append(Bar(date: day.date, observed: 0, forecast: day.precipitationAmount ?? 0, isToday: false))
        }
        totals.dailyBars = bars
        return totals
    }
}
