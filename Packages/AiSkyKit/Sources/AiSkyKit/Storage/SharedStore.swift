import Foundation

/// Values baked into the app's Info.plist at build time (see `Config/Shared.xcconfig`).
public enum BuildConfiguration {
    /// Info.plist key holding the App Group identifier shared by the app and widgets.
    public static let appGroupInfoKey = "AiSkyAppGroup"
    /// Info.plist key that is `YES` when the build was signed with the WeatherKit entitlement.
    public static let weatherKitInfoKey = "AiSkyWeatherKitEnabled"

    public static var appGroupIdentifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: appGroupInfoKey) as? String,
              !value.isEmpty, !value.contains("$(") else {
            return nil
        }
        return value
    }

    /// Whether this build includes the WeatherKit entitlement. Without it, Apple Weather
    /// requests fail, so the app goes straight to Open-Meteo.
    public static var isWeatherKitEnabled: Bool {
        switch Bundle.main.object(forInfoDictionaryKey: weatherKitInfoKey) {
        case let value as Bool: return value
        case let value as String: return ["yes", "true", "1"].contains(value.lowercased())
        case let value as NSNumber: return value.boolValue
        default: return false
        }
    }
}

/// Persistent storage shared between the app and its widget extension through an App Group.
/// Falls back to the process' own storage if the App Group isn't configured, so the app
/// still works (the widgets just won't see the library).
public final class SharedStore: @unchecked Sendable {
    public static let shared = SharedStore()

    public enum Key: String {
        case settings = "aisky.settings.v1"
        case savedLocations = "aisky.savedLocations.v1"
        case currentLocation = "aisky.currentLocation.v1"
        case lastSelectedLocationID = "aisky.lastSelectedLocation.v1"
        case weatherKitFailure = "aisky.weatherKitFailure.v1"
        case notifiedAlertIDs = "aisky.notifiedAlertIDs.v1"
        case lastRainNotification = "aisky.lastRainNotification.v1"
    }

    public let defaults: UserDefaults
    public let appGroupIdentifier: String?
    public let isUsingAppGroup: Bool
    /// Root directory for caches (inside the App Group container when available).
    public let cachesDirectory: URL

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(appGroupIdentifier: String? = BuildConfiguration.appGroupIdentifier) {
        self.appGroupIdentifier = appGroupIdentifier
        var groupDefaults: UserDefaults?
        var groupContainer: URL?
        if let appGroupIdentifier {
            groupDefaults = UserDefaults(suiteName: appGroupIdentifier)
            #if canImport(Darwin)
            groupContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
            #endif
        }
        self.defaults = groupDefaults ?? .standard
        self.isUsingAppGroup = groupDefaults != nil && groupContainer != nil
        let base = groupContainer?.appendingPathComponent("Library/Caches", isDirectory: true)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.cachesDirectory = base.appendingPathComponent("AiSky", isDirectory: true)
    }

    /// For tests: explicit defaults + directory.
    public init(defaults: UserDefaults, cachesDirectory: URL) {
        self.defaults = defaults
        self.appGroupIdentifier = nil
        self.isUsingAppGroup = false
        self.cachesDirectory = cachesDirectory
    }

    // MARK: Generic Codable values

    public func value<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    public func set<T: Encodable>(_ value: T?, forKey key: Key) {
        guard let value else {
            defaults.removeObject(forKey: key.rawValue)
            return
        }
        if let data = try? encoder.encode(value) {
            defaults.set(data, forKey: key.rawValue)
        }
    }

    // MARK: Typed accessors

    public func loadSettings() -> AppSettings {
        value(AppSettings.self, forKey: .settings) ?? AppSettings.defaults()
    }

    public func saveSettings(_ settings: AppSettings) {
        set(settings, forKey: .settings)
    }

    public func loadSavedLocations() -> [SavedLocation] {
        value([SavedLocation].self, forKey: .savedLocations) ?? []
    }

    public func saveSavedLocations(_ locations: [SavedLocation]) {
        set(Array(locations.prefix(LocationLibrary.maximumLocations)), forKey: .savedLocations)
    }

    public func loadCurrentLocation() -> CurrentLocationSnapshot? {
        value(CurrentLocationSnapshot.self, forKey: .currentLocation)
    }

    public func saveCurrentLocation(_ snapshot: CurrentLocationSnapshot?) {
        set(snapshot, forKey: .currentLocation)
    }

    /// All locations in display order: the device location (if known) followed by the library.
    public func loadAllWeatherLocations(includeCurrent: Bool = true) -> [WeatherLocation] {
        var result: [WeatherLocation] = []
        if includeCurrent, let current = loadCurrentLocation() {
            result.append(.current(current))
        }
        result += loadSavedLocations().map(WeatherLocation.init(saved:))
        return result
    }

    public func weatherLocation(id: String) -> WeatherLocation? {
        if id == WeatherLocation.currentLocationID {
            return loadCurrentLocation().map(WeatherLocation.current)
        }
        return loadSavedLocations().first { $0.id.uuidString == id }.map(WeatherLocation.init(saved:))
    }
}
