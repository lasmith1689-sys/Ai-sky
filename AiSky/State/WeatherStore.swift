import AiSkyKit
import Foundation
import Observation
import WidgetKit

/// Observable cache of forecasts for the UI. Data comes from ``WeatherRepository`` and is
/// shared on disk with the widgets.
@MainActor
@Observable
final class WeatherStore {
    private(set) var snapshots: [String: WeatherSnapshot] = [:]
    private(set) var summaries: [String: LocationWeatherSummary] = [:]
    private(set) var loadingIDs: Set<String> = []
    private(set) var errors: [String: String] = [:]

    private let repository: WeatherRepository
    @ObservationIgnored private var lastWidgetReload = Date.distantPast
    /// Fetches under way, so a second request for the same place waits for the first instead of
    /// being dropped.
    @ObservationIgnored private var inFlight: [String: (location: WeatherLocation, task: Task<Void, Never>)] = [:]

    /// Forecasts younger than this are shown without refetching. While the app stays open, the
    /// forecast on screen is refetched once it's this old.
    nonisolated static let freshness: TimeInterval = 5 * 60
    /// Opening the app, or coming back to it, refetches the forecast on screen once it's older
    /// than this.
    nonisolated static let freshnessOnOpen: TimeInterval = 60

    #if DEBUG
    /// `-AiSkyDemoWeather`: sample weather everywhere, for deterministic screenshots of every look.
    static let usesDemoWeather = ProcessInfo.processInfo.arguments.contains("-AiSkyDemoWeather")

    /// `-AiSkyDemoSky <condition>[-night]` (with `-AiSkyDemoWeather`): the sample's current sky,
    /// e.g. `clear`, `snow` or `cloudy-night`, for screenshots of Liquid on each kind of sky.
    static let demoSky: (condition: SkyCondition, isDaylight: Bool)? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-AiSkyDemoSky"), arguments.indices.contains(index + 1) else { return nil }
        let value = arguments[index + 1]
        let night = value.hasSuffix("-night")
        guard let condition = SkyCondition(rawValue: night ? String(value.dropLast(6)) : value) else { return nil }
        return (condition, !night)
    }()

    /// The sample weather, with the `-AiSkyDemoSky` sky applied: a dry sky also dries the next
    /// hour (so the yesterday comparison shows), a wet one is raining now and stops within the
    /// hour (so the rate line shows).
    static func demoSnapshot(for location: WeatherLocation) -> WeatherSnapshot {
        var snapshot = SampleData.snapshot(now: Date(), location: location)
        if let sky = demoSky {
            snapshot.current.condition = sky.condition
            snapshot.current.isDaylight = sky.isDaylight
            if var nextHour = snapshot.nextHour {
                let kind = sky.condition.precipitationKind
                let start = nextHour.minutes.first?.date ?? Date()
                nextHour.minutes = nextHour.minutes.map { minute in
                    var minute = minute
                    let offset = minute.date.timeIntervalSince(start) / 60
                    let wet = sky.condition.isPrecipitation && offset < 34
                    minute.intensity = wet ? 1.1 + sin(offset / 3) * 0.4 : 0
                    minute.chance = wet ? 0.9 : 0.05
                    minute.kind = wet ? kind : .none
                    return minute
                }
                snapshot.nextHour = nextHour
            }
            snapshot.current.precipitationIntensity = sky.condition.isPrecipitation ? 1.2 : 0
        }
        return snapshot
    }
    #endif

    init(repository: WeatherRepository) {
        self.repository = repository
    }

    func snapshot(for id: String) -> WeatherSnapshot? { snapshots[id] }

    func isLoading(_ id: String) -> Bool { loadingIDs.contains(id) }

    func error(for id: String) -> String? { errors[id] }

    /// Newest available summary: from a full forecast or from the lightweight list request.
    func summary(for id: String) -> LocationWeatherSummary? {
        let fromSnapshot = snapshots[id]?.summary
        let direct = summaries[id]
        switch (fromSnapshot, direct) {
        case let (a?, b?): return a.fetchedAt >= b.fetchedAt ? a : b
        case let (a?, nil): return a
        case let (nil, b?): return b
        default: return nil
        }
    }

    func loadCached(for locations: [WeatherLocation]) async {
        #if DEBUG
        if Self.usesDemoWeather { return }
        #endif
        for location in locations where snapshots[location.id] == nil {
            // A fetch can finish while the cache is read; keep its newer forecast.
            if let cached = await repository.cachedSnapshot(for: location), snapshots[location.id] == nil {
                snapshots[location.id] = cached
            }
        }
        let cachedSummaries = await repository.cache.allSummaries()
        for (id, summary) in cachedSummaries where summaries[id] == nil {
            summaries[id] = summary
        }
    }

    /// Fetches `location`'s forecast unless the one on hand is younger than `maxAge` and from the
    /// right source (see ``WeatherRepository/canReuse(_:settings:maxAge:now:)``). `force` always fetches.
    func refresh(_ location: WeatherLocation, settings: AppSettings, maxAge: TimeInterval = WeatherStore.freshness, force: Bool = false) async {
        #if DEBUG
        if Self.usesDemoWeather {
            let snapshot = Self.demoSnapshot(for: location)
            snapshots[location.id] = snapshot
            summaries[location.id] = snapshot.summary
            errors[location.id] = nil
            return
        }
        #endif
        // A fetch already under way for this spot answers this request too. One for where the
        // device used to be is followed by a fetch for where it is now.
        while let running = inFlight[location.id] {
            await running.task.value
            if running.location.distance(toLatitude: location.latitude, longitude: location.longitude) < 3 { return }
        }
        if !force, let existing = snapshots[location.id],
           repository.canReuse(existing, settings: settings, maxAge: maxAge),
           existing.location.distance(toLatitude: location.latitude, longitude: location.longitude) < 3 {
            return
        }
        loadingIDs.insert(location.id)
        // Not tied to the caller, so a page swiped away still finishes and caches its forecast.
        let task = Task {
            defer {
                inFlight[location.id] = nil
                loadingIDs.remove(location.id)
            }
            await load(location, settings: settings, maxAge: maxAge, force: force)
        }
        inFlight[location.id] = (location, task)
        await task.value
    }

    private func load(_ location: WeatherLocation, settings: AppSettings, maxAge: TimeInterval, force: Bool) async {
        do {
            let snapshot = force
                ? try await repository.fetch(for: location, settings: settings)
                : try await repository.snapshot(for: location, settings: settings, maxAge: maxAge)
            snapshots[location.id] = snapshot
            summaries[location.id] = snapshot.summary
            errors[location.id] = nil
            reloadWidgetsIfNeeded()
        } catch is CancellationError {
            // Keep what we have.
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            errors[location.id] = error.localizedDescription
        }
    }

    func refreshSummaries(for locations: [WeatherLocation], settings: AppSettings, force: Bool = false) async {
        #if DEBUG
        if Self.usesDemoWeather {
            for location in locations {
                summaries[location.id] = Self.demoSnapshot(for: location).summary
            }
            return
        }
        #endif
        let result = await repository.summaries(for: locations, settings: settings, maxAge: force ? 0 : 15 * 60)
        for (id, summary) in result {
            summaries[id] = summary
        }
    }

    func remove(locationID: String) {
        snapshots[locationID] = nil
        summaries[locationID] = nil
        errors[locationID] = nil
        let cache = repository.cache
        Task { await cache.remove(locationID: locationID) }
    }

    private func reloadWidgetsIfNeeded() {
        guard Date().timeIntervalSince(lastWidgetReload) > 60 else { return }
        lastWidgetReload = Date()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
