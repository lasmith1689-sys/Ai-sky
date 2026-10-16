import AiSkyKit
import Foundation
import Observation

/// Loads rainfall history for one place: two years of daily totals (enough for every preset
/// and its "last year" comparison), extra years for custom ranges, and 1991–2020 normals.
@MainActor
@Observable
final class RainHistoryModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// Periods offered on the screen (Precip's presets plus any range).
    enum Choice: String, CaseIterable, Identifiable {
        case week, thirtyDays, month, year, twelveMonths, custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .week: return "7 Days"
            case .thirtyDays: return "30 Days"
            case .month: return "This Month"
            case .year: return "This Year"
            case .twelveMonths: return "12 Months"
            case .custom: return "Custom"
            }
        }
    }

    /// Custom ranges are limited to ten years to keep requests reasonable.
    static let maximumCustomDays = 3653

    let location: WeatherLocation
    let calendar: Calendar
    private(set) var record: RainfallRecord
    private(set) var state: LoadState = .idle
    private(set) var normalsState: LoadState = .idle

    var choice: Choice = .thirtyDays
    var customStart: Date
    var customEnd: Date

    @ObservationIgnored private var coveredRanges: [ClosedRange<Date>] = []
    private let store: WeatherHistoryStore

    init(location: WeatherLocation, snapshot: WeatherSnapshot?, store: WeatherHistoryStore = .shared, now: Date = Date()) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot?.timeZone
            ?? location.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? .current
        self.location = location
        self.calendar = calendar
        self.store = store
        let today = calendar.startOfDay(for: now)
        self.customEnd = today
        self.customStart = calendar.date(byAdding: .month, value: -3, to: today) ?? today
        var record = RainfallRecord(calendar: calendar)
        // Today so far comes from the live forecast; the history services only have whole days.
        if let snapshot, let todaySoFar = PrecipitationTotals.compute(for: snapshot, now: now).todaySoFar {
            record.merge([PrecipitationSample(date: today, amount: todaySoFar)])
        }
        self.record = record
    }

    var today: Date { calendar.startOfDay(for: Date()) }

    var earliestDate: Date { WeatherHistoryClient.earliestDate(calendar: calendar) }

    var period: RainfallPeriod {
        switch choice {
        case .week: return .last7Days
        case .thirtyDays: return .last30Days
        case .month: return .monthToDate
        case .year: return .yearToDate
        case .twelveMonths: return .last12Months
        case .custom: return .custom(start: customStart, end: customEnd)
        }
    }

    /// The days currently shown.
    var range: ClosedRange<Date> { period.dateRange(today: Date(), calendar: calendar) }

    var hasData: Bool { record.days.count > 1 }

    var failureMessage: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    var isLoading: Bool { state == .loading }

    func load() async {
        guard state == .idle else { return }
        async let normals: Void = loadNormals()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let twoYearsAgo = calendar.date(byAdding: .year, value: -2, to: today) ?? today
        await fetch(twoYearsAgo...yesterday)
        await normals
        await loadPeriodIfNeeded()
    }

    func retry() async {
        state = .idle
        coveredRanges = []
        await load()
    }

    /// Custom ranges outside the two-year window (plus the year before, for comparison).
    func loadPeriodIfNeeded() async {
        guard choice == .custom, state != .loading else { return }
        let range = self.range
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return }
        let lastNeeded = min(range.upperBound, yesterday)
        let firstNeeded = max(calendar.date(byAdding: .year, value: -1, to: range.lowerBound) ?? range.lowerBound, earliestDate)
        guard firstNeeded <= lastNeeded else { return }
        if coveredRanges.contains(where: { $0.contains(firstNeeded) && $0.contains(lastNeeded) }) {
            return
        }
        await fetch(firstNeeded...lastNeeded)
    }

    /// Keeps custom dates valid: ordered, not in the future, at most ten years apart.
    func normalizeCustomRange() {
        let end = min(max(calendar.startOfDay(for: customEnd), earliestDate), today)
        var start = min(max(calendar.startOfDay(for: customStart), earliestDate), end)
        if let limit = calendar.date(byAdding: .day, value: -Self.maximumCustomDays, to: end), start < limit {
            start = limit
        }
        if customEnd != end { customEnd = end }
        if customStart != start { customStart = start }
    }

    private func fetch(_ range: ClosedRange<Date>) async {
        state = .loading
        do {
            let samples = try await store.dailyPrecipitation(for: location, range: range, calendar: calendar)
            record.merge(samples)
            coveredRanges.append(range)
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func loadNormals() async {
        guard record.normals == nil else { return }
        normalsState = .loading
        do {
            record.normals = try await store.precipitationNormals(for: location)
            normalsState = .loaded
        } catch {
            normalsState = .failed(error.localizedDescription)
        }
    }
}
