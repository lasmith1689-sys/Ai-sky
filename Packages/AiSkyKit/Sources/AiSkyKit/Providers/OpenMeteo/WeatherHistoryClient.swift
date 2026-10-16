import Foundation

/// Weather for any date: Dark Sky's "Time Machine" and Precip-style long-range rainfall records.
///
/// Recent days (about three months) come from Open-Meteo's forecast API, which keeps the
/// high-resolution model data it served at the time. Older dates come from its historical
/// archive (ERA5, ERA5-Land and ECMWF IFS reanalysis), which reaches back to 1940.
public struct WeatherHistoryClient: Sendable {
    public static let archiveEndpoint = URL(string: "https://archive-api.open-meteo.com/v1/archive")!
    /// The forecast API keeps 93 days of past data; stay safely inside that.
    public static let recentDays = 85
    /// How far ahead the forecast API reaches.
    public static let forecastDays = 15
    /// The current WMO climate normal period.
    public static let normalPeriod = 1991...2020

    static let hourlyVariables = [
        "temperature_2m", "apparent_temperature", "relative_humidity_2m", "dew_point_2m", "precipitation",
        "snowfall", "weather_code", "cloud_cover", "pressure_msl", "wind_speed_10m", "wind_direction_10m",
        "wind_gusts_10m", "is_day",
    ]
    /// Only the forecast API has these.
    static let recentHourlyVariables = ["precipitation_probability", "uv_index", "visibility"]
    static let dailyVariables = [
        "weather_code", "temperature_2m_max", "temperature_2m_min", "apparent_temperature_max",
        "apparent_temperature_min", "sunrise", "sunset", "precipitation_sum", "snowfall_sum",
        "precipitation_hours", "wind_speed_10m_max", "wind_gusts_10m_max", "wind_direction_10m_dominant",
    ]
    static let recentDailyVariables = ["uv_index_max", "precipitation_probability_max"]

    enum Endpoint: Equatable {
        case forecast, archive
    }

    struct Segment: Equatable {
        var endpoint: Endpoint
        /// Local midnight of the first day.
        var start: Date
        /// Local midnight of the last day (inclusive).
        var end: Date
    }

    let http: HTTPClient

    public init(http: HTTPClient = HTTPClient(timeout: 40)) {
        self.http = http
    }

    /// First day with data (January 1, 1940) in `calendar`'s time zone.
    public static func earliestDate(calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 1940, month: 1, day: 1)) ?? Date(timeIntervalSince1970: -946_771_200)
    }

    /// Last day with data (the end of the forecast).
    public static func latestDate(today: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: forecastDays, to: calendar.startOfDay(for: today)) ?? today
    }

    // MARK: Requests

    /// Daily precipitation totals for the local days `start...end`.
    public func dailyPrecipitation(
        latitude: Double,
        longitude: Double,
        from start: Date,
        to end: Date,
        calendar: Calendar,
        today: Date = Date()
    ) async throws -> [PrecipitationSample] {
        let segments = Self.segments(from: start, to: end, today: today, calendar: calendar)
        let urls = segments.map {
            Self.url(for: $0, latitude: latitude, longitude: longitude, calendar: calendar, daily: ["precipitation_sum", "snowfall_sum"])
        }
        let http = self.http
        let parts = try await withThrowingTaskGroup(of: [PrecipitationSample].self) { group in
            for url in urls {
                group.addTask {
                    Self.dailySamples(from: try await http.decode(OMForecastResponse.self, from: url).daily)
                }
            }
            var all: [PrecipitationSample] = []
            for try await part in group {
                all += part
            }
            return all
        }
        return Self.merged(parts)
    }

    /// Hour-by-hour weather and the day's summary for one local day, past or future.
    public func day(for location: WeatherLocation, date: Date, calendar: Calendar, today: Date = Date()) async throws -> HistoricalDay {
        let day = calendar.startOfDay(for: date)
        guard day >= Self.earliestDate(calendar: calendar), day <= Self.latestDate(today: today, calendar: calendar) else {
            throw WeatherServiceError.noData
        }
        let url = Self.dayURL(latitude: location.latitude, longitude: location.longitude, date: day, calendar: calendar, today: today)
        let response = try await http.decode(OMForecastResponse.self, from: url)
        return try Self.historicalDay(from: response, date: day, calendar: calendar, today: today)
    }

    /// Average daily precipitation over 1991–2020, for "compared with normal".
    public func precipitationNormals(latitude: Double, longitude: Double) async throws -> PrecipitationNormals {
        let url = Self.normalsURL(latitude: latitude, longitude: longitude)
        let response = try await http.decode(OMForecastResponse.self, from: url)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = response.timezone.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "UTC")!
        guard let normals = PrecipitationNormals.compute(
            from: Self.dailySamples(from: response.daily),
            calendar: calendar,
            years: Self.normalPeriod
        ) else {
            throw WeatherServiceError.noData
        }
        return normals
    }

    // MARK: Request planning

    /// Splits `start...end` between the archive (older days) and the forecast API (recent and future days).
    static func segments(from start: Date, to end: Date, today: Date, calendar: Calendar) -> [Segment] {
        let first = max(calendar.startOfDay(for: start), earliestDate(calendar: calendar))
        let last = min(calendar.startOfDay(for: end), latestDate(today: today, calendar: calendar))
        guard first <= last,
              let recentStart = calendar.date(byAdding: .day, value: -recentDays, to: calendar.startOfDay(for: today)),
              let archiveLast = calendar.date(byAdding: .day, value: -1, to: recentStart) else {
            return []
        }
        var result: [Segment] = []
        if first < recentStart {
            result.append(Segment(endpoint: .archive, start: first, end: min(last, archiveLast)))
        }
        if last >= recentStart {
            result.append(Segment(endpoint: .forecast, start: max(first, recentStart), end: last))
        }
        return result
    }

    static func url(
        for segment: Segment,
        latitude: Double,
        longitude: Double,
        calendar: Calendar,
        hourly: [String] = [],
        daily: [String] = []
    ) -> URL {
        url(
            endpoint: segment.endpoint,
            latitude: latitude,
            longitude: longitude,
            startDate: dayString(segment.start, calendar: calendar),
            endDate: dayString(segment.end, calendar: calendar),
            hourly: hourly,
            daily: daily
        )
    }

    /// The requested day plus the next one: Open-Meteo reports each hour's precipitation at the
    /// end of the hour, so the day's last hour is stamped at the following midnight.
    static func dayURL(latitude: Double, longitude: Double, date: Date, calendar: Calendar, today: Date) -> URL {
        let recentStart = calendar.date(byAdding: .day, value: -recentDays, to: calendar.startOfDay(for: today)) ?? today
        let endpoint: Endpoint = date < recentStart ? .archive : .forecast
        let next = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        let end = min(next, latestDate(today: today, calendar: calendar))
        return url(
            endpoint: endpoint,
            latitude: latitude,
            longitude: longitude,
            startDate: dayString(date, calendar: calendar),
            endDate: dayString(end, calendar: calendar),
            hourly: endpoint == .forecast ? hourlyVariables + recentHourlyVariables : hourlyVariables,
            daily: endpoint == .forecast ? dailyVariables + recentDailyVariables : dailyVariables
        )
    }

    static func normalsURL(latitude: Double, longitude: Double) -> URL {
        url(
            endpoint: .archive,
            latitude: latitude,
            longitude: longitude,
            startDate: "\(normalPeriod.lowerBound)-01-01",
            endDate: "\(normalPeriod.upperBound)-12-31",
            daily: ["precipitation_sum"]
        )
    }

    private static func url(
        endpoint: Endpoint,
        latitude: Double,
        longitude: Double,
        startDate: String,
        endDate: String,
        hourly: [String] = [],
        daily: [String] = []
    ) -> URL {
        let base = endpoint == .archive ? archiveEndpoint : OpenMeteoClient.forecastEndpoint
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "latitude", value: OpenMeteoClient.coordinate(latitude)),
            URLQueryItem(name: "longitude", value: OpenMeteoClient.coordinate(longitude)),
            URLQueryItem(name: "start_date", value: startDate),
            URLQueryItem(name: "end_date", value: endDate),
        ]
        if !hourly.isEmpty {
            items.append(URLQueryItem(name: "hourly", value: hourly.joined(separator: ",")))
        }
        if !daily.isEmpty {
            items.append(URLQueryItem(name: "daily", value: daily.joined(separator: ",")))
        }
        if endpoint == .forecast {
            // Open-Meteo blends 15-minute models (HRRR, ICON-D2, AROME) into past values only when
            // current or 15-minute data is requested, as the main forecast does. Ask for it too so
            // the same day never shows two different totals.
            items.append(URLQueryItem(name: "current", value: "temperature_2m"))
        }
        items.append(URLQueryItem(name: "timezone", value: "auto"))
        items.append(URLQueryItem(name: "timeformat", value: "unixtime"))
        components.queryItems = items
        return components.url!
    }

    /// "2024-07-04" for the local day containing `date`.
    static func dayString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: Mapping

    static func dailySamples(from daily: OMDaily?) -> [PrecipitationSample] {
        guard let daily else { return [] }
        return daily.time.indices.compactMap { index in
            guard let amount = daily.precipitationSum.value(at: index) else { return nil }
            return PrecipitationSample(
                date: Date(timeIntervalSince1970: daily.time[index]),
                amount: amount,
                snowfall: daily.snowfallSum.value(at: index)
            )
        }
    }

    /// Sorted by date, one sample per day.
    static func merged(_ samples: [PrecipitationSample]) -> [PrecipitationSample] {
        var byDate: [Date: PrecipitationSample] = [:]
        for sample in samples {
            byDate[sample.date] = sample
        }
        return byDate.values.sorted { $0.date < $1.date }
    }

    static func historicalDay(from response: OMForecastResponse, date: Date, calendar: Calendar, today: Date) throws -> HistoricalDay {
        let timeZoneID = response.timezone ?? calendar.timeZone.identifier
        let startOfToday = calendar.startOfDay(for: today)
        let recentStart = calendar.date(byAdding: .day, value: -recentDays, to: startOfToday) ?? startOfToday
        let isPast = date < startOfToday
        var summary = response.daily.flatMap { OpenMeteoMapper.day(from: $0, at: 0) }
        // The response starts at the requested day, so its first daily timestamp is that day's midnight.
        let dayStart = response.daily?.time.first.map { Date(timeIntervalSince1970: $0) } ?? date
        let dayEnd = response.daily?.time[safe: 1].map { Date(timeIntervalSince1970: $0) } ?? dayStart.addingTimeInterval(24 * 3600)
        var hours = (response.hourly.map(OpenMeteoMapper.hourly(from:)) ?? [])
            .filter { $0.date >= dayStart && $0.date < dayEnd }
        guard summary != nil || !hours.isEmpty else {
            throw WeatherServiceError.noData
        }
        if isPast {
            // What fell matters for past days, not what was once forecast.
            summary?.precipitationChance = nil
            for index in hours.indices {
                hours[index].precipitationChance = nil
            }
        }
        return HistoricalDay(
            date: dayStart,
            timeZoneIdentifier: timeZoneID,
            summary: summary,
            hours: hours,
            source: date < recentStart ? .reanalysis : .forecastModels,
            isForecast: date > startOfToday,
            isToday: date == startOfToday
        )
    }
}
