import AiSkyKit
import CoreLocation
import Foundation

/// Resolves which place a widget shows and fetches (or reuses) its forecast.
enum WidgetDataLoader {
    /// Widgets reuse the app's cached forecast when it is recent, otherwise fetch from
    /// Open-Meteo directly (the widget extension doesn't carry the WeatherKit entitlement).
    static let repository = WeatherRepository(weatherKitAvailable: false)
    static let maxCacheAge: TimeInterval = 20 * 60

    struct LoadResult {
        var location: WeatherLocation?
        var snapshot: WeatherSnapshot?
        var settings: AppSettings
        var errorMessage: String?
    }

    static func load(locationID: String?) async -> LoadResult {
        let store = SharedStore.shared
        let settings = store.loadSettings()
        guard let location = await resolveLocation(id: locationID, store: store) else {
            return LoadResult(location: nil, snapshot: nil, settings: settings, errorMessage: nil)
        }
        do {
            let snapshot = try await repository.snapshot(for: location, settings: settings, maxAge: maxCacheAge)
            return LoadResult(location: location, snapshot: snapshot, settings: settings)
        } catch {
            // Offline: show the last forecast we have, even if it's old.
            let cached = await repository.cachedSnapshot(for: location)
            return LoadResult(location: location, snapshot: cached, settings: settings, errorMessage: cached == nil ? error.localizedDescription : nil)
        }
    }

    static func resolveLocation(id: String?, store: SharedStore) async -> WeatherLocation? {
        let requested = id ?? WeatherLocation.currentLocationID
        if requested != WeatherLocation.currentLocationID, let saved = store.weatherLocation(id: requested) {
            return saved
        }
        if let fresh = await WidgetLocationFetcher.currentLocation(store: store) {
            return fresh
        }
        if let cached = store.loadCurrentLocation() {
            return .current(cached)
        }
        return store.loadSavedLocations().first.map(WeatherLocation.init(saved:))
    }
}

/// One-shot location fix for widgets (requires "While Using" permission granted in the app and
/// `NSWidgetWantsLocation` in the extension's Info.plist).
@MainActor
final class WidgetLocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    static func currentLocation(store: SharedStore) async -> WeatherLocation? {
        let fetcher = WidgetLocationFetcher()
        guard let location = await fetcher.fetch() else { return nil }

        // Reuse the name the app resolved if we're still nearby.
        if let cached = store.loadCurrentLocation(),
           GeoMath.distanceKm(lat1: cached.latitude, lon1: cached.longitude,
                              lat2: location.coordinate.latitude, lon2: location.coordinate.longitude) < 2 {
            var updated = cached
            updated.latitude = location.coordinate.latitude
            updated.longitude = location.coordinate.longitude
            updated.updatedAt = Date()
            store.saveCurrentLocation(updated)
            return .current(updated)
        }
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let snapshot = CurrentLocationSnapshot(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            name: placemark?.locality ?? placemark?.name,
            subtitle: placemark?.administrativeArea,
            timeZoneIdentifier: placemark?.timeZone?.identifier ?? TimeZone.current.identifier,
            countryCode: placemark?.isoCountryCode
        )
        store.saveCurrentLocation(snapshot)
        return .current(snapshot)
    }

    private func fetch() async -> CLLocation? {
        guard manager.isAuthorizedForWidgetUpdates else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyKilometer
            manager.requestLocation()
            // Widgets have a tight time budget; give up on a slow fix and use the cached location.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                self?.finish(nil)
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        MainActor.assumeIsolated { finish(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finish(nil) }
    }
}
