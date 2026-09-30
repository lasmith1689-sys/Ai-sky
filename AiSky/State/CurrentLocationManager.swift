import AiSkyKit
import CoreLocation
import Foundation
import Observation

/// Wraps Core Location: permission, one-shot location fixes and reverse geocoding.
@MainActor
@Observable
final class CurrentLocationManager {
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var isUpdating = false
    private(set) var lastError: String?

    /// Called with each new fix after the place name has been resolved.
    @ObservationIgnored var onUpdate: ((CurrentLocationSnapshot) -> Void)?
    /// Called when the user turns location access off.
    @ObservationIgnored var onAuthorizationRevoked: (() -> Void)?

    private let manager = CLLocationManager()
    private let delegate = LocationDelegate()
    @ObservationIgnored private var pending: [CheckedContinuation<CLLocation?, Never>] = []
    @ObservationIgnored private var lastPlace: (location: CLLocation, snapshot: CurrentLocationSnapshot)?

    init() {
        authorizationStatus = manager.authorizationStatus
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.delegate = delegate
        delegate.onAuthorizationChange = { [weak self] status in
            guard let self else { return }
            let wasAuthorized = self.isAuthorized
            self.authorizationStatus = status
            if self.isAuthorized && !wasAuthorized {
                Task { await self.refresh() }
            } else if self.isDenied {
                self.onAuthorizationRevoked?()
            }
        }
        delegate.onLocations = { [weak self] locations in
            self?.finish(with: locations.last)
        }
        delegate.onFailure = { [weak self] error in
            self?.lastError = error.localizedDescription
            self?.finish(with: nil)
        }
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    var canRequestAuthorization: Bool { authorizationStatus == .notDetermined }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Gets a fresh fix, resolves its name and reports it through ``onUpdate``.
    func refresh() async {
        guard isAuthorized, !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        guard let location = await requestLocation() else { return }
        let snapshot = await makeSnapshot(for: location)
        onUpdate?(snapshot)
    }

    private func requestLocation() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            pending.append(continuation)
            guard pending.count == 1 else { return }
            manager.requestLocation()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                self?.finish(with: nil)
            }
        }
    }

    private func finish(with location: CLLocation?) {
        let continuations = pending
        pending = []
        for continuation in continuations {
            continuation.resume(returning: location)
        }
    }

    private func makeSnapshot(for location: CLLocation) async -> CurrentLocationSnapshot {
        if let lastPlace, lastPlace.location.distance(from: location) < 1_000 {
            var snapshot = lastPlace.snapshot
            snapshot.latitude = location.coordinate.latitude
            snapshot.longitude = location.coordinate.longitude
            snapshot.updatedAt = Date()
            return snapshot
        }
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let name = placemark?.locality ?? placemark?.subAdministrativeArea ?? placemark?.name
        let subtitle = [placemark?.administrativeArea, placemark?.country]
            .compactMap { $0 }
            .joined(separator: ", ")
        let snapshot = CurrentLocationSnapshot(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            name: name,
            subtitle: subtitle.isEmpty ? nil : subtitle,
            timeZoneIdentifier: placemark?.timeZone?.identifier ?? TimeZone.current.identifier,
            countryCode: placemark?.isoCountryCode
        )
        if placemark != nil {
            lastPlace = (location, snapshot)
        }
        return snapshot
    }
}

/// Plain NSObject delegate that forwards Core Location callbacks to the main actor.
private final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    var onAuthorizationChange: (@MainActor (CLAuthorizationStatus) -> Void)?
    var onLocations: (@MainActor ([CLLocation]) -> Void)?
    var onFailure: (@MainActor (Error) -> Void)?

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated { onAuthorizationChange?(status) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated { onLocations?(locations) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { onFailure?(error) }
    }
}
