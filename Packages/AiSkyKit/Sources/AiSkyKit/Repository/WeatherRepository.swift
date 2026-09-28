import Foundation

/// Single entry point for weather data used by the app, widgets and background tasks.
///
/// * Apple Weather (WeatherKit) is used when the build has the entitlement and the user
///   hasn't chosen Open-Meteo. Open-Meteo is always fetched in parallel: it supplies the
///   precipitation history and acts as an automatic fallback if Apple Weather fails.
/// * Air quality always comes from Open-Meteo (CAMS models).
/// * U.S. alerts come from the National Weather Service when Apple Weather isn't in use.
public struct WeatherRepository: Sendable {
    public let openMeteo: OpenMeteoClient
    public let nws: NWSAlertsClient
    public let cache: SnapshotCache
    public let store: SharedStore
    /// Overrides ``BuildConfiguration/isWeatherKitEnabled`` (tests / previews).
    public let weatherKitAvailable: Bool

    public init(
        openMeteo: OpenMeteoClient = OpenMeteoClient(),
        nws: NWSAlertsClient = NWSAlertsClient(),
        cache: SnapshotCache = .shared,
        store: SharedStore = .shared,
        weatherKitAvailable: Bool = BuildConfiguration.isWeatherKitEnabled
    ) {
        self.openMeteo = openMeteo
        self.nws = nws
        self.cache = cache
        self.store = store
        self.weatherKitAvailable = weatherKitAvailable
    }

    public static let shared = WeatherRepository()

    // MARK: Provider selection

    /// Seconds to skip Apple Weather after it fails (e.g. missing entitlement).
    static let weatherKitBackoff: TimeInterval = 15 * 60

    struct WeatherKitFailure: Codable {
        var date: Date
        var message: String
    }

    public func shouldUseWeatherKit(_ settings: AppSettings, now: Date = Date()) -> Bool {
        guard weatherKitAvailable, settings.dataSource != .openMeteo else { return false }
        #if canImport(WeatherKit)
        if let failure = store.value(WeatherKitFailure.self, forKey: .weatherKitFailure),
           now.timeIntervalSince(failure.date) < Self.weatherKitBackoff {
            return false
        }
        return true
        #else
        return false
        #endif
    }

    /// Message explaining why Apple Weather isn't being used, if the user asked for it.
    public func weatherKitStatusMessage(_ settings: AppSettings) -> String? {
        guard settings.dataSource != .openMeteo else { return nil }
        if !weatherKitAvailable {
            return settings.dataSource == .appleWeather
                ? "Apple Weather isn't enabled in this build. See the README to turn on WeatherKit."
                : nil
        }
        if let failure = store.value(WeatherKitFailure.self, forKey: .weatherKitFailure),
           Date().timeIntervalSince(failure.date) < Self.weatherKitBackoff {
            return "Apple Weather is temporarily unavailable (\(failure.message)). Using Open-Meteo."
        }
        return nil
    }

    private func recordWeatherKitFailure(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        store.set(WeatherKitFailure(date: Date(), message: String(message.prefix(120))), forKey: .weatherKitFailure)
    }

    private func clearWeatherKitFailure() {
        store.set(Optional<WeatherKitFailure>.none, forKey: .weatherKitFailure)
    }

    // MARK: Full forecast

    /// Returns the cached snapshot when it is younger than `maxAge`, otherwise fetches a new one.
    public func snapshot(
        for location: WeatherLocation,
        settings: AppSettings,
        maxAge: TimeInterval = 10 * 60,
        now: Date = Date()
    ) async throws -> WeatherSnapshot {
        if let cached = await cachedSnapshot(for: location), cached.isFresh(maxAge: maxAge, now: now) {
            return cached
        }
        return try await fetch(for: location, settings: settings, now: now)
    }

    /// Cached snapshot for the location, ignoring it if the device has moved far away since.
    public func cachedSnapshot(for location: WeatherLocation) async -> WeatherSnapshot? {
        guard let cached = await cache.snapshot(for: location.id) else { return nil }
        let moved = cached.location.distance(toLatitude: location.latitude, longitude: location.longitude)
        return moved < 3 ? cached : nil
    }

    public func fetch(for location: WeatherLocation, settings: AppSettings, now: Date = Date()) async throws -> WeatherSnapshot {
        let useWeatherKit = shouldUseWeatherKit(settings, now: now)
        let wantsNWS = location.isLikelyInUnitedStates

        async let openMeteoResult = capture { try await openMeteo.forecast(for: location, now: now) }
        async let airQualityResult = capture { try await openMeteo.airQuality(for: location) }
        async let weatherKitResult = captureIf(useWeatherKit) { try await weatherKitForecast(for: location, now: now) }
        async let nwsResult = captureIf(wantsNWS && !useWeatherKit) {
            try await nws.activeAlerts(latitude: location.latitude, longitude: location.longitude)
        }

        let openMeteoSnapshot = await openMeteoResult
        let weatherKitSnapshot = await weatherKitResult
        let airQuality = await airQualityResult
        var nwsAlerts = await nwsResult

        var notes: [String] = []
        var snapshot: WeatherSnapshot
        switch (weatherKitSnapshot, openMeteoSnapshot) {
        case (.success(var appleSnapshot)?, let openMeteo):
            clearWeatherKitFailure()
            if case .success(let fallback) = openMeteo {
                if location.timeZoneIdentifier == nil {
                    appleSnapshot.timeZoneIdentifier = fallback.timeZoneIdentifier
                    appleSnapshot.location.timeZoneIdentifier = fallback.timeZoneIdentifier
                }
                appleSnapshot.precipitationHistory = fallback.precipitationHistory
                if appleSnapshot.nextHour == nil {
                    appleSnapshot.nextHour = fallback.nextHour
                    notes.append("Minute-by-minute precipitation isn't available here; next-hour chart uses 15-minute Open-Meteo data.")
                }
                // Apple's hourly range can start at the current hour; keep Open-Meteo's recent
                // past hours for charts.
                if let firstApple = appleSnapshot.hourly.first?.date {
                    let earlier = fallback.hourly.filter { $0.date < firstApple }
                    appleSnapshot.hourly = earlier + appleSnapshot.hourly
                }
            }
            snapshot = appleSnapshot
        case (.failure(let error)?, .success(let fallback)):
            recordWeatherKitFailure(error)
            snapshot = fallback
            notes.append("Apple Weather was unavailable, so this forecast uses Open-Meteo.")
            if wantsNWS {
                nwsAlerts = await capture { try await nws.activeAlerts(latitude: location.latitude, longitude: location.longitude) }
            }
        case (nil, .success(let fallback)):
            snapshot = fallback
        case (_, .failure(let error)):
            throw error
        }

        if case .success(let value) = airQuality {
            snapshot.airQuality = value
        }
        if snapshot.source == .openMeteo, case .success(let alerts)? = nwsAlerts {
            snapshot.alerts = alerts
        }
        if let message = weatherKitStatusMessage(settings), snapshot.source == .openMeteo, !notes.contains(message) {
            notes.append(message)
        }
        snapshot.location.name = location.name
        snapshot.location.subtitle = location.subtitle
        snapshot.notes = notes
        await cache.store(snapshot)
        return snapshot
    }

    private func weatherKitForecast(for location: WeatherLocation, now: Date) async throws -> WeatherSnapshot {
        #if canImport(WeatherKit)
        return try await WeatherKitProvider().forecast(for: location, now: now)
        #else
        throw WeatherServiceError.weatherKitUnavailable("WeatherKit is not available on this platform")
        #endif
    }

    // MARK: Library summaries

    /// Current conditions for many locations, reusing fresh cache entries.
    public func summaries(
        for locations: [WeatherLocation],
        settings: AppSettings,
        maxAge: TimeInterval = 15 * 60,
        now: Date = Date()
    ) async -> [String: LocationWeatherSummary] {
        var result = await cache.allSummaries().filter { entry in locations.contains { $0.id == entry.key } }
        let stale = locations.filter { location in
            guard let summary = result[location.id] else { return true }
            return now.timeIntervalSince(summary.fetchedAt) >= maxAge
        }
        guard !stale.isEmpty else { return result }

        var fetched: [LocationWeatherSummary] = []
        var remaining = stale
        #if canImport(WeatherKit)
        if shouldUseWeatherKit(settings, now: now) {
            let provider = WeatherKitProvider()
            let appleSummaries = await withTaskGroup(of: LocationWeatherSummary?.self) { group in
                for location in stale {
                    group.addTask { try? await provider.summary(for: location, now: now) }
                }
                var collected: [LocationWeatherSummary] = []
                for await summary in group {
                    if let summary { collected.append(summary) }
                }
                return collected
            }
            fetched += appleSummaries
            let done = Set(appleSummaries.map(\.locationID))
            remaining = stale.filter { !done.contains($0.id) }
        }
        #endif
        if !remaining.isEmpty, let openMeteoSummaries = try? await openMeteo.summaries(for: remaining, now: now) {
            fetched += openMeteoSummaries
        }
        await cache.store(summaries: fetched)
        for summary in fetched {
            result[summary.locationID] = summary
        }
        return result
    }

    // MARK: Lightweight queries for background alerts

    public func nextHour(for location: WeatherLocation, settings: AppSettings, now: Date = Date()) async throws -> NextHourForecast? {
        #if canImport(WeatherKit)
        if shouldUseWeatherKit(settings, now: now) {
            do {
                if let forecast = try await WeatherKitProvider().nextHour(for: location) {
                    return forecast
                }
            } catch {
                recordWeatherKitFailure(error)
            }
        }
        #endif
        return try await openMeteo.nextHour(for: location, now: now)
    }

    public func alerts(for location: WeatherLocation, settings: AppSettings, now: Date = Date()) async throws -> [WeatherAlertInfo] {
        #if canImport(WeatherKit)
        if shouldUseWeatherKit(settings, now: now) {
            do {
                return try await WeatherKitProvider().alerts(for: location)
            } catch {
                recordWeatherKitFailure(error)
            }
        }
        #endif
        guard location.isLikelyInUnitedStates else { return [] }
        return try await nws.activeAlerts(latitude: location.latitude, longitude: location.longitude)
    }
}

// MARK: - Helpers

func capture<T: Sendable>(_ operation: @Sendable () async throws -> T) async -> Result<T, Error> {
    do {
        return .success(try await operation())
    } catch {
        return .failure(error)
    }
}

func captureIf<T: Sendable>(_ condition: Bool, _ operation: @Sendable () async throws -> T) async -> Result<T, Error>? {
    guard condition else { return nil }
    return await capture(operation)
}
