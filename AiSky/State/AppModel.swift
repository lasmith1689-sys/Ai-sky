import AiSkyKit
import Foundation
import Observation
import SwiftUI
import UserNotifications
import WidgetKit

enum AppTab: Hashable {
    case forecast
    case radar
    case locations
    case settings
}

/// Sections of the forecast that deep links (e.g. from widgets) can scroll to.
enum ForecastSection: String, Hashable {
    case nextHour
    case hourly
    case daily
    case precipitation
    case airQuality
    case details
}

/// Screens presented over the forecast that deep links can open.
enum ForecastSheet: String, Hashable, Identifiable {
    case rainHistory
    case timeMachine

    var id: String { rawValue }
}

/// Root app state: settings, the 20-location library, the device location and weather data.
@MainActor
@Observable
final class AppModel {
    let store: SharedStore
    let repository: WeatherRepository
    let weather: WeatherStore
    let locationManager: CurrentLocationManager

    /// Persisted by ``settingsChanged(from:to:)`` (called from `RootView.onChange`).
    var settings: AppSettings
    private(set) var savedLocations: [SavedLocation]
    private(set) var currentLocation: CurrentLocationSnapshot?

    var selectedTab: AppTab = .forecast
    /// ``WeatherLocation/id`` of the page shown in the Forecast tab.
    var selectedLocationID: String?
    /// Set to open the "Add Location" sheet from anywhere.
    var isAddingLocation = false
    /// Forecast section to scroll to (set by deep links, consumed by `ForecastView`).
    var pendingSection: ForecastSection?
    /// Sheet to open over the forecast (set by deep links, consumed by `ForecastView`).
    var pendingSheet: ForecastSheet?

    @ObservationIgnored private var lastActiveRefresh: Date?
    private let notificationRouter = NotificationRouter()

    init(store: SharedStore = .shared, repository: WeatherRepository = .shared) {
        self.store = store
        self.repository = repository
        self.settings = store.loadSettings()
        self.savedLocations = store.loadSavedLocations()
        self.currentLocation = store.loadCurrentLocation()
        self.weather = WeatherStore(repository: repository)
        self.locationManager = CurrentLocationManager()
        self.selectedLocationID = store.defaults.string(forKey: SharedStore.Key.lastSelectedLocationID.rawValue)
        locationManager.onUpdate = { [weak self] snapshot in
            self?.currentLocationUpdated(snapshot)
        }
        locationManager.onAuthorizationRevoked = { [weak self] in
            self?.forgetCurrentLocation()
        }
        notificationRouter.onOpenURL = { [weak self] url in
            self?.handle(url: url)
        }
        UNUserNotificationCenter.current().delegate = notificationRouter
        #if DEBUG
        applyDebugLaunchArguments()
        #endif
    }

    #if DEBUG
    /// Debug-only launch arguments used by the CI smoke test (handy in the Simulator too):
    /// `-AiSkyDemoLibrary` fills an empty library with sample places;
    /// `-AiSkyScreen radar|locations|settings|<forecast section>|rainHistory|timeMachine` opens that screen.
    private func applyDebugLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-AiSkyDemoLibrary"), savedLocations.isEmpty {
            savedLocations = Array(SampleData.savedLocations.dropFirst())
            store.saveSavedLocations(savedLocations)
        }
        if let index = arguments.firstIndex(of: "-AiSkyScreen"), arguments.indices.contains(index + 1) {
            switch arguments[index + 1] {
            case "radar": selectedTab = .radar
            case "locations": selectedTab = .locations
            case "settings": selectedTab = .settings
            default:
                selectedTab = .forecast
                pendingSection = ForecastSection(rawValue: arguments[index + 1])
                pendingSheet = ForecastSheet(rawValue: arguments[index + 1])
            }
        }
    }
    #endif

    // MARK: Derived data

    var formatter: WeatherFormatter { WeatherFormatter(units: settings.units) }

    var showsCurrentLocation: Bool {
        locationManager.isAuthorized && currentLocation != nil
    }

    /// Pages of the Forecast tab: the device location first, then the library.
    var forecastLocations: [WeatherLocation] {
        var locations: [WeatherLocation] = []
        if showsCurrentLocation, let currentLocation {
            locations.append(.current(currentLocation))
        }
        locations += savedLocations.map(WeatherLocation.init(saved:))
        return locations
    }

    var selectedLocation: WeatherLocation? {
        let locations = forecastLocations
        return locations.first { $0.id == selectedLocationID } ?? locations.first
    }

    var canAddLocation: Bool { LocationLibrary.canAdd(to: savedLocations) }

    // MARK: Lifecycle

    func start() async {
        await weather.loadCached(for: forecastLocations)
        if locationManager.isAuthorized {
            await locationManager.refresh()
        }
        await refreshSelected()
    }

    func appDidBecomeActive() {
        // Avoid double work right after launch; otherwise refresh anything stale.
        if let lastActiveRefresh, Date().timeIntervalSince(lastActiveRefresh) < 60 { return }
        lastActiveRefresh = Date()
        Task {
            if locationManager.isAuthorized {
                await locationManager.refresh()
            }
            await refreshSelected()
        }
    }

    func refreshSelected(force: Bool = false) async {
        guard let location = selectedLocation else { return }
        await weather.refresh(location, settings: settings, force: force)
    }

    func refresh(_ location: WeatherLocation, force: Bool = false) async {
        await weather.refresh(location, settings: settings, force: force)
        if let snapshot = weather.snapshot(for: location.id) {
            learnTimeZone(snapshot)
        }
    }

    func refreshLibrarySummaries(force: Bool = false) async {
        await weather.refreshSummaries(for: forecastLocations, settings: settings, force: force)
    }

    // MARK: Selection & navigation

    func select(locationID: String, showForecast: Bool = true) {
        selectedLocationID = locationID
        store.defaults.set(locationID, forKey: SharedStore.Key.lastSelectedLocationID.rawValue)
        if showForecast {
            selectedTab = .forecast
        }
    }

    /// `aisky://forecast/<id>?section=airQuality`, `aisky://radar`, `aisky://locations`, `aisky://settings`
    func handle(url: URL) {
        guard url.scheme == "aisky" else { return }
        switch url.host {
        case "forecast":
            let id = url.pathComponents.dropFirst().first
            if let id, forecastLocations.contains(where: { $0.id == id }) {
                select(locationID: id)
            } else {
                selectedTab = .forecast
            }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            pendingSection = items.first { $0.name == "section" }?.value.flatMap(ForecastSection.init(rawValue:))
            pendingSheet = items.first { $0.name == "show" }?.value.flatMap(ForecastSheet.init(rawValue:))
        case "radar":
            selectedTab = .radar
        case "locations":
            selectedTab = .locations
        case "settings":
            selectedTab = .settings
        default:
            break
        }
    }

    // MARK: Library (max 20)

    @discardableResult
    func addLocation(_ location: SavedLocation) throws -> SavedLocation {
        savedLocations = try LocationLibrary.adding(location, to: savedLocations)
        persistLibrary()
        let weatherLocation = WeatherLocation(saved: location)
        Task { await refresh(weatherLocation) }
        return location
    }

    func removeLocations(at offsets: IndexSet) {
        let ids = Set(offsets.compactMap { savedLocations.indices.contains($0) ? savedLocations[$0].id : nil })
        removeLocations(ids: ids)
    }

    func removeLocations(ids: Set<UUID>) {
        savedLocations = LocationLibrary.removing(ids: ids, from: savedLocations)
        for id in ids {
            weather.remove(locationID: id.uuidString)
            settings.rainAlertLocationIDs.removeAll { $0 == id.uuidString }
        }
        persistLibrary()
    }

    func moveLocations(from source: IndexSet, to destination: Int) {
        savedLocations = LocationLibrary.moving(savedLocations, fromOffsets: source, toOffset: destination)
        persistLibrary()
    }

    func renameLocation(id: UUID, to name: String?) {
        savedLocations = LocationLibrary.renaming(id: id, to: name, in: savedLocations)
        persistLibrary()
    }

    private func persistLibrary() {
        store.saveSavedLocations(savedLocations)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Saved places get their time zone from the first forecast if search didn't provide one.
    private func learnTimeZone(_ snapshot: WeatherSnapshot) {
        let updated = LocationLibrary.updating(id: snapshot.location.id, timeZoneIdentifier: snapshot.timeZoneIdentifier, in: savedLocations)
        if updated != savedLocations {
            savedLocations = updated
            store.saveSavedLocations(updated)
        }
    }

    // MARK: Device location

    private func currentLocationUpdated(_ snapshot: CurrentLocationSnapshot) {
        let moved = currentLocation.map {
            GeoMath.distanceKm(lat1: $0.latitude, lon1: $0.longitude, lat2: snapshot.latitude, lon2: snapshot.longitude)
        } ?? .infinity
        currentLocation = snapshot
        store.saveCurrentLocation(snapshot)
        if moved > 1 {
            WidgetCenter.shared.reloadAllTimelines()
            Task { await refresh(.current(snapshot), force: moved > 3) }
        }
        if selectedLocationID == nil {
            selectedLocationID = WeatherLocation.currentLocationID
        }
    }

    /// Location access was turned off: stop showing (and sharing with widgets) the old position.
    private func forgetCurrentLocation() {
        guard currentLocation != nil else { return }
        currentLocation = nil
        store.saveCurrentLocation(nil)
        weather.remove(locationID: WeatherLocation.currentLocationID)
        if selectedLocationID == WeatherLocation.currentLocationID {
            selectedLocationID = nil
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Settings

    func settingsChanged(from old: AppSettings, to new: AppSettings) {
        store.saveSettings(new)
        WidgetCenter.shared.reloadAllTimelines()
        if old.dataSource != new.dataSource {
            Task { await refreshSelected(force: true) }
        }
        if new.rainAlertsEnabled || new.severeAlertsEnabled {
            BackgroundRefresher.schedule()
        }
    }
}
