import Foundation

/// Which weather provider to use for forecasts.
public enum DataSourcePreference: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Apple Weather when WeatherKit is enabled for this build, otherwise Open-Meteo.
    case automatic
    case appleWeather
    case openMeteo

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .appleWeather: return "Apple Weather"
        case .openMeteo: return "Open-Meteo"
        }
    }
}

/// Which radar mosaic the Radar tab shows.
public enum RadarSourcePreference: String, Codable, CaseIterable, Sendable, Identifiable {
    /// NOAA NEXRAD over the U.S., RainViewer elsewhere.
    case automatic
    case noaa
    case rainViewer

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .noaa: return "NOAA NEXRAD (U.S.)"
        case .rainViewer: return "RainViewer (Global)"
        }
    }
}

public enum MapStylePreference: String, Codable, CaseIterable, Sendable, Identifiable {
    case muted
    case standard
    case hybrid
    case satellite

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .muted: return "Muted"
        case .standard: return "Standard"
        case .hybrid: return "Hybrid"
        case .satellite: return "Satellite"
        }
    }
}

/// User preferences shared by the app and its widgets (stored in the App Group).
public struct AppSettings: Codable, Sendable, Equatable {
    public var units: UnitPreferences
    public var dataSource: DataSourcePreference
    public var aqiScale: AQIScale
    public var radarSource: RadarSourcePreference
    public var radarOpacity: Double
    /// Frames per second for radar playback.
    public var radarSpeed: Double
    public var radarMapStyle: MapStylePreference
    /// Notify when precipitation is about to start ("Rain starting in 10 min").
    public var rainAlertsEnabled: Bool
    /// ``WeatherLocation/id``s to watch for rain alerts.
    public var rainAlertLocationIDs: [String]
    /// Notify about new government weather alerts for watched locations.
    public var severeAlertsEnabled: Bool
    /// Visual style of the app and widgets.
    public var look: Look

    public init(
        units: UnitPreferences,
        dataSource: DataSourcePreference = .automatic,
        aqiScale: AQIScale = .us,
        radarSource: RadarSourcePreference = .automatic,
        radarOpacity: Double = 0.75,
        radarSpeed: Double = 2.5,
        radarMapStyle: MapStylePreference = .muted,
        rainAlertsEnabled: Bool = false,
        rainAlertLocationIDs: [String] = [WeatherLocation.currentLocationID],
        severeAlertsEnabled: Bool = false,
        look: Look = .default
    ) {
        self.units = units
        self.dataSource = dataSource
        self.aqiScale = aqiScale
        self.radarSource = radarSource
        self.radarOpacity = radarOpacity
        self.radarSpeed = radarSpeed
        self.radarMapStyle = radarMapStyle
        self.rainAlertsEnabled = rainAlertsEnabled
        self.rainAlertLocationIDs = rainAlertLocationIDs
        self.severeAlertsEnabled = severeAlertsEnabled
        self.look = look
    }

    /// Defaults for the user's region (imperial + US AQI in the U.S., metric + EAQI in Europe...).
    public static func defaults(for locale: Locale = .autoupdatingCurrent) -> AppSettings {
        let units = UnitPreferences.defaults(for: locale)
        let region = locale.region?.identifier.uppercased() ?? ""
        let europe: Set<String> = [
            "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV",
            "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE", "GB", "NO", "CH", "IS",
        ]
        return AppSettings(units: units, aqiScale: europe.contains(region) ? .european : .us)
    }

    public var formatter: WeatherFormatter { WeatherFormatter(units: units) }

    // Decoding tolerates missing keys so settings survive app updates.
    private enum CodingKeys: String, CodingKey {
        case units, dataSource, aqiScale, radarSource, radarOpacity, radarSpeed, radarMapStyle
        case rainAlertsEnabled, rainAlertLocationIDs, severeAlertsEnabled, look
    }

    public init(from decoder: Decoder) throws {
        let defaults = AppSettings.defaults()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        units = (try? c.decodeIfPresent(UnitPreferences.self, forKey: .units)) ?? defaults.units
        dataSource = (try? c.decodeIfPresent(DataSourcePreference.self, forKey: .dataSource)) ?? defaults.dataSource
        aqiScale = (try? c.decodeIfPresent(AQIScale.self, forKey: .aqiScale)) ?? defaults.aqiScale
        radarSource = (try? c.decodeIfPresent(RadarSourcePreference.self, forKey: .radarSource)) ?? defaults.radarSource
        radarOpacity = (try? c.decodeIfPresent(Double.self, forKey: .radarOpacity)) ?? defaults.radarOpacity
        radarSpeed = (try? c.decodeIfPresent(Double.self, forKey: .radarSpeed)) ?? defaults.radarSpeed
        radarMapStyle = (try? c.decodeIfPresent(MapStylePreference.self, forKey: .radarMapStyle)) ?? defaults.radarMapStyle
        rainAlertsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .rainAlertsEnabled)) ?? defaults.rainAlertsEnabled
        rainAlertLocationIDs = (try? c.decodeIfPresent([String].self, forKey: .rainAlertLocationIDs)) ?? defaults.rainAlertLocationIDs
        severeAlertsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .severeAlertsEnabled)) ?? defaults.severeAlertsEnabled
        // Settings saved before looks existed have no key: they get the default (Instrument) too.
        look = (try? c.decodeIfPresent(Look.self, forKey: .look)) ?? .default
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(units, forKey: .units)
        try c.encode(dataSource, forKey: .dataSource)
        try c.encode(aqiScale, forKey: .aqiScale)
        try c.encode(radarSource, forKey: .radarSource)
        try c.encode(radarOpacity, forKey: .radarOpacity)
        try c.encode(radarSpeed, forKey: .radarSpeed)
        try c.encode(radarMapStyle, forKey: .radarMapStyle)
        try c.encode(rainAlertsEnabled, forKey: .rainAlertsEnabled)
        try c.encode(rainAlertLocationIDs, forKey: .rainAlertLocationIDs)
        try c.encode(severeAlertsEnabled, forKey: .severeAlertsEnabled)
        try c.encode(look, forKey: .look)
    }
}
