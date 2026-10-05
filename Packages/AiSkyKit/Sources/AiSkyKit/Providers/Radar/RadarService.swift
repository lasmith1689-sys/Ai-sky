import Foundation

public enum RadarSource: String, Codable, CaseIterable, Sendable, Identifiable {
    /// NOAA NEXRAD base-reflectivity mosaic via the Iowa Environmental Mesonet. U.S. only,
    /// high resolution, 5-minute updates.
    case noaa
    /// RainViewer global composite (free tier: past 2 hours, zoom ≤ 7).
    case rainViewer

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .noaa: return "NOAA NEXRAD"
        case .rainViewer: return "RainViewer"
        }
    }

    public var attribution: String {
        switch self {
        case .noaa: return "Radar: NOAA NWS NEXRAD via Iowa Environmental Mesonet"
        case .rainViewer: return "Radar: RainViewer.com"
        }
    }

    public var attributionURL: URL {
        switch self {
        case .noaa: return URL(string: "https://mesonet.agron.iastate.edu/ogc/")!
        case .rainViewer: return URL(string: "https://www.rainviewer.com/api.html")!
        }
    }
}

/// One animation frame of radar imagery, addressed as XYZ map tiles.
public struct RadarFrame: Sendable, Hashable, Identifiable {
    public var id: String
    public var time: Date
    /// Template containing `{z}`, `{x}`, `{y}` and optionally `{size}` (256/512).
    public var tileURLTemplate: String
    /// Highest zoom the server provides; deeper zooms must be up-scaled client-side.
    public var maxNativeZoom: Int
    public var isForecast: Bool

    public init(id: String, time: Date, tileURLTemplate: String, maxNativeZoom: Int, isForecast: Bool = false) {
        self.id = id
        self.time = time
        self.tileURLTemplate = tileURLTemplate
        self.maxNativeZoom = maxNativeZoom
        self.isForecast = isForecast
    }

    public var supportsHighResolutionTiles: Bool { tileURLTemplate.contains("{size}") }

    public func tileURL(z: Int, x: Int, y: Int, highResolution: Bool) -> URL? {
        let urlString = tileURLTemplate
            .replacingOccurrences(of: "{size}", with: highResolution ? "512" : "256")
            .replacingOccurrences(of: "{z}", with: String(z))
            .replacingOccurrences(of: "{x}", with: String(x))
            .replacingOccurrences(of: "{y}", with: String(y))
        return URL(string: urlString)
    }
}

public struct RadarTimeline: Sendable, Equatable {
    public var source: RadarSource
    public var frames: [RadarFrame]
    public var fetchedAt: Date

    public init(source: RadarSource, frames: [RadarFrame], fetchedAt: Date) {
        self.source = source
        self.frames = frames.sorted { $0.time < $1.time }
        self.fetchedAt = fetchedAt
    }

    /// Index of the most recent observed (non-forecast) frame.
    public var latestObservedIndex: Int? {
        frames.lastIndex { !$0.isForecast }
    }
}

public struct RadarService: Sendable {
    public static let rainViewerMapsURL = URL(string: "https://api.rainviewer.com/public/weather-maps.json")!
    public static let noaaLatestMetadataURL = URL(string: "https://mesonet.agron.iastate.edu/data/gis/images/4326/USCOMP/n0q_0.json")!

    let http: HTTPClient

    public init(http: HTTPClient = HTTPClient(timeout: 15)) {
        self.http = http
    }

    /// Picks NOAA over the U.S. and RainViewer elsewhere when the preference is automatic.
    public static func resolve(_ preference: RadarSourcePreference, latitude: Double, longitude: Double) -> RadarSource {
        switch preference {
        case .noaa: return .noaa
        case .rainViewer: return .rainViewer
        case .automatic:
            return GeoMath.isInUnitedStatesCoverage(latitude: latitude, longitude: longitude) ? .noaa : .rainViewer
        }
    }

    public func timeline(for source: RadarSource, now: Date = Date()) async throws -> RadarTimeline {
        switch source {
        case .rainViewer:
            let data = try await http.data(from: Self.rainViewerMapsURL)
            return try Self.parseRainViewer(data, now: now)
        case .noaa:
            var latest: Date?
            if let data = try? await http.data(from: Self.noaaLatestMetadataURL) {
                latest = Self.parseNOAAValidTime(data)
            }
            return Self.noaaTimeline(latestValidTime: latest, now: now)
        }
    }

    // MARK: RainViewer

    static func parseRainViewer(_ data: Data, now: Date) throws -> RadarTimeline {
        let maps: RainViewerMaps
        do {
            maps = try JSONDecoder().decode(RainViewerMaps.self, from: data)
        } catch {
            throw WeatherServiceError.decoding(String(describing: error))
        }
        let host = maps.host ?? "https://tilecache.rainviewer.com"
        func frame(_ item: RainViewerMaps.Frame, forecast: Bool) -> RadarFrame {
            RadarFrame(
                id: "rv-\(item.path)",
                time: Date(timeIntervalSince1970: item.time),
                // Universal Blue (2) with smoothing and snow colors (1_1) — the free tier's scheme.
                tileURLTemplate: "\(host)\(item.path)/{size}/{z}/{x}/{y}/2/1_1.png",
                maxNativeZoom: 7,
                isForecast: forecast
            )
        }
        let past = maps.radar?.past?.map { frame($0, forecast: false) } ?? []
        let nowcast = maps.radar?.nowcast?.map { frame($0, forecast: true) } ?? []
        guard !past.isEmpty || !nowcast.isEmpty else { throw WeatherServiceError.noData }
        return RadarTimeline(source: .rainViewer, frames: past + nowcast, fetchedAt: now)
    }

    // MARK: NOAA (Iowa Environmental Mesonet tile cache)

    /// IEM publishes the current mosaic plus layers for 5, 10, … 50 minutes ago.
    static func noaaTimeline(latestValidTime: Date?, now: Date) -> RadarTimeline {
        let latest = latestValidTime ?? estimatedNOAAValidTime(now: now)
        let frames = stride(from: 50, through: 0, by: -5).map { minutesAgo -> RadarFrame in
            let layer = minutesAgo == 0 ? "nexrad-n0q-900913" : String(format: "nexrad-n0q-900913-m%02dm", minutesAgo)
            return RadarFrame(
                id: "noaa-\(layer)-\(Int(latest.timeIntervalSince1970))",
                time: latest.addingTimeInterval(-Double(minutesAgo) * 60),
                tileURLTemplate: "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/\(layer)/{z}/{x}/{y}.png",
                maxNativeZoom: 10
            )
        }
        return RadarTimeline(source: .noaa, frames: frames, fetchedAt: now)
    }

    /// The mosaic is produced every 5 minutes and usually lags a few minutes.
    static func estimatedNOAAValidTime(now: Date) -> Date {
        let lagged = now.timeIntervalSince1970 - 5 * 60
        return Date(timeIntervalSince1970: (lagged / 300).rounded(.down) * 300)
    }

    static func parseNOAAValidTime(_ data: Data) -> Date? {
        struct Metadata: Decodable {
            struct Meta: Decodable { let valid: String? }
            let meta: Meta?
        }
        guard let valid = (try? JSONDecoder().decode(Metadata.self, from: data))?.meta?.valid else { return nil }
        return NWSAlertsClient.parseDate(valid)
    }
}

struct RainViewerMaps: Decodable {
    struct Frame: Decodable {
        let time: TimeInterval
        let path: String
    }

    struct Radar: Decodable {
        let past: [Frame]?
        let nowcast: [Frame]?
    }

    let host: String?
    let radar: Radar?
}
