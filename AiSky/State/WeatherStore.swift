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

    /// Forecasts younger than this are shown without refetching.
    static let freshness: TimeInterval = 10 * 60

    #if DEBUG
    /// `-AiSkyDemoWeather`: sample weather everywhere, for deterministic screenshots of every look.
    static let usesDemoWeather = ProcessInfo.processInfo.arguments.contains("-AiSkyDemoWeather")
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
            if let cached = await repository.cachedSnapshot(for: location) {
                snapshots[location.id] = cached
            }
        }
        let cachedSummaries = await repository.cache.allSummaries()
        for (id, summary) in cachedSummaries where summaries[id] == nil {
            summaries[id] = summary
        }
    }

    func refresh(_ location: WeatherLocation, settings: AppSettings, force: Bool = false) async {
        #if DEBUG
        if Self.usesDemoWeather {
            let snapshot = SampleData.snapshot(now: Date(), location: location)
            snapshots[location.id] = snapshot
            summaries[location.id] = snapshot.summary
            errors[location.id] = nil
            return
        }
        #endif
        if !force, let existing = snapshots[location.id], existing.isFresh(maxAge: Self.freshness),
           existing.location.distance(toLatitude: location.latitude, longitude: location.longitude) < 3 {
            return
        }
        guard !loadingIDs.contains(location.id) else { return }
        loadingIDs.insert(location.id)
        defer { loadingIDs.remove(location.id) }

        do {
            let snapshot = force
                ? try await repository.fetch(for: location, settings: settings)
                : try await repository.snapshot(for: location, settings: settings, maxAge: Self.freshness)
            snapshots[location.id] = snapshot
            summaries[location.id] = snapshot.summary
            errors[location.id] = nil
            reloadWidgetsIfNeeded()
        } catch is CancellationError {
            // View went away; keep what we have.
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            errors[location.id] = error.localizedDescription
        }
    }

    func refreshSummaries(for locations: [WeatherLocation], settings: AppSettings, force: Bool = false) async {
        #if DEBUG
        if Self.usesDemoWeather {
            for location in locations {
                summaries[location.id] = SampleData.snapshot(now: Date(), location: location).summary
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
