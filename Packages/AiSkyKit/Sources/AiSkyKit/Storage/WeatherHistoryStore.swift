import Foundation

/// Fetches and caches rainfall history, climate normals and Time Machine days.
///
/// Normals never change, so they are kept on disk; daily totals and days are kept in memory.
public actor WeatherHistoryStore {
    public static let shared = WeatherHistoryStore(
        directory: SharedStore.shared.cachesDirectory.appendingPathComponent("History", isDirectory: true)
    )

    /// Recent daily totals can still be revised, so refetch after a while.
    static let dailyMaxAge: TimeInterval = 3 * 3600
    /// Days at least this old are final; newer ones (and forecasts) expire.
    static let settledAge: TimeInterval = 3 * 24 * 3600
    static let recentDayMaxAge: TimeInterval = 30 * 60

    private struct CachedRange {
        var range: ClosedRange<Date>
        var fetchedAt: Date
        var samples: [PrecipitationSample]
    }

    private let client: WeatherHistoryClient
    private let directory: URL
    private var ranges: [String: [CachedRange]] = [:]
    private var normals: [String: PrecipitationNormals] = [:]
    private var days: [String: (fetchedAt: Date, day: HistoricalDay)] = [:]

    public init(client: WeatherHistoryClient = WeatherHistoryClient(), directory: URL) {
        self.client = client
        self.directory = directory
    }

    /// Daily precipitation totals for the local days in `range`.
    public func dailyPrecipitation(
        for location: WeatherLocation,
        range: ClosedRange<Date>,
        calendar: Calendar,
        now: Date = Date()
    ) async throws -> [PrecipitationSample] {
        let key = Self.coordinateKey(location)
        if let cached = ranges[key]?.first(where: {
            $0.range.contains(range.lowerBound) && $0.range.contains(range.upperBound)
                && now.timeIntervalSince($0.fetchedAt) < Self.dailyMaxAge
        }) {
            return cached.samples.filter { range.contains($0.date) }
        }
        let samples = try await client.dailyPrecipitation(
            latitude: location.latitude,
            longitude: location.longitude,
            from: range.lowerBound,
            to: range.upperBound,
            calendar: calendar,
            today: now
        )
        var entries = ranges[key, default: []].filter { now.timeIntervalSince($0.fetchedAt) < Self.dailyMaxAge }
        entries.append(CachedRange(range: range, fetchedAt: now, samples: samples))
        ranges[key] = Array(entries.suffix(6))
        return samples
    }

    /// 1991–2020 normals, from disk when available.
    public func precipitationNormals(for location: WeatherLocation) async throws -> PrecipitationNormals {
        let key = Self.coordinateKey(location)
        if let cached = normals[key] {
            return cached
        }
        let file = directory.appendingPathComponent("normals-\(key).json")
        if let data = try? Data(contentsOf: file),
           let stored = try? JSONDecoder().decode(PrecipitationNormals.self, from: data) {
            normals[key] = stored
            return stored
        }
        let fetched = try await client.precipitationNormals(latitude: location.latitude, longitude: location.longitude)
        normals[key] = fetched
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(fetched) {
            try? data.write(to: file, options: .atomic)
        }
        return fetched
    }

    /// One day of weather for the Time Machine.
    public func day(
        for location: WeatherLocation,
        date: Date,
        calendar: Calendar,
        now: Date = Date()
    ) async throws -> HistoricalDay {
        let dayStart = calendar.startOfDay(for: date)
        let key = "\(Self.coordinateKey(location))-\(WeatherHistoryClient.dayString(dayStart, calendar: calendar))"
        if let cached = days[key] {
            let settled = now.timeIntervalSince(dayStart) > Self.settledAge
            if settled || now.timeIntervalSince(cached.fetchedAt) < Self.recentDayMaxAge {
                return cached.day
            }
        }
        let day = try await client.day(for: location, date: dayStart, calendar: calendar, today: now)
        if days.count > 60 {
            days.removeAll()
        }
        days[key] = (now, day)
        return day
    }

    /// About 1 km: close enough to share cached history between nearby coordinates.
    static func coordinateKey(_ location: WeatherLocation) -> String {
        String(format: "%.2f_%.2f", locale: Locale(identifier: "en_US_POSIX"), location.latitude, location.longitude)
    }
}
