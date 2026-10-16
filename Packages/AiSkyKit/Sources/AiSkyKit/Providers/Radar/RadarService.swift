import Foundation

public enum RadarSource: String, Codable, CaseIterable, Sendable, Identifiable {
    /// NOAA NEXRAD base-reflectivity mosaic via the Iowa Environmental Mesonet, plus the NOAA HRRR
    /// model's forecast reflectivity for the next two hours. Contiguous U.S., 5-minute updates.
    case noaa
    /// RainViewer global composite (free tier since January 2026: past 2 hours only, zoom ≤ 7,
    /// no forecast).
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
        case .noaa: return "Radar: NOAA NEXRAD · Forecast: NOAA HRRR · via Iowa Environmental Mesonet"
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
    /// Stable for the same imagery: a refresh that still includes this frame keeps its id, so its
    /// cached tiles are reused.
    public var id: String
    public var time: Date
    /// Template containing `{z}`, `{x}`, `{y}`, and optionally `{s}`, a host shard (see `hostShards`).
    /// Every template names its imagery's time explicitly, so a tile URL never changes content and
    /// can be cached for as long as it's useful.
    public var tileURLTemplate: String
    /// Highest zoom the server provides; deeper zooms draw the native tile enlarged.
    public var maxNativeZoom: Int
    public var isForecast: Bool
    /// Values substituted for `{s}`. Each tile always maps to the same shard, so caching still works,
    /// while tiles spread over hosts that each allow their own set of connections.
    public var hostShards: [String]

    public init(
        id: String,
        time: Date,
        tileURLTemplate: String,
        maxNativeZoom: Int,
        isForecast: Bool = false,
        hostShards: [String] = []
    ) {
        self.id = id
        self.time = time
        self.tileURLTemplate = tileURLTemplate
        self.maxNativeZoom = maxNativeZoom
        self.isForecast = isForecast
        self.hostShards = hostShards
    }

    public func tileURL(z: Int, x: Int, y: Int) -> URL? {
        var urlString = tileURLTemplate
            .replacingOccurrences(of: "{z}", with: String(z))
            .replacingOccurrences(of: "{x}", with: String(x))
            .replacingOccurrences(of: "{y}", with: String(y))
        if !hostShards.isEmpty {
            let shard = hostShards[abs(x &+ y) % hostShards.count]
            urlString = urlString.replacingOccurrences(of: "{s}", with: shard)
        }
        return URL(string: urlString)
    }

    public func tileURL(for key: RadarTileKey) -> URL? {
        tileURL(z: key.z, x: key.x, y: key.y)
    }
}

public struct RadarTimeline: Sendable, Equatable {
    public var source: RadarSource
    public var frames: [RadarFrame]
    public var fetchedAt: Date
    /// Initialization time of the model run the forecast frames come from, when there are any.
    public var forecastRunTime: Date?

    public init(source: RadarSource, frames: [RadarFrame], fetchedAt: Date, forecastRunTime: Date? = nil) {
        self.source = source
        self.frames = frames.sorted { $0.time < $1.time }
        self.fetchedAt = fetchedAt
        self.forecastRunTime = forecastRunTime
    }

    /// Index of the most recent observed (non-forecast) frame: "now" on the timeline.
    public var latestObservedIndex: Int? {
        frames.lastIndex { !$0.isForecast }
    }

    public var hasForecast: Bool { frames.contains { $0.isForecast } }
}

public struct RadarService: Sendable {
    public static let rainViewerMapsURL = URL(string: "https://api.rainviewer.com/public/weather-maps.json")!
    public static let noaaLatestMetadataURL = URL(string: "https://mesonet.agron.iastate.edu/data/gis/images/4326/USCOMP/n0q_0.json")!
    /// Metadata for the last forecast step (18 hours) of the newest HRRR run the IEM has finished
    /// processing, so every earlier step of that run is available too.
    public static let hrrrMetadataURL = URL(string: "https://mesonet.agron.iastate.edu/data/gis/images/4326/hrrr/refd_1080.json")!

    /// The IEM's documented DNS aliases (mesonet, mesonet1, mesonet2, mesonet3) for parallel tile requests.
    static let iemShards = ["", "1", "2", "3"]
    static let iemHost = "https://mesonet{s}.agron.iastate.edu"

    /// Past radar frames: every 5 minutes for the last 50.
    static let pastMinutes = 50
    /// Forecast frames: every 15 minutes (the HRRR output step) for the next 2 hours.
    public static let forecastHorizonMinutes = 120
    static let forecastStepMinutes = 15
    static let hrrrMaxLeadMinutes = 1080
    /// A run older than this is skipped: its forecast would be a long-range guess, and an old run
    /// usually means the IEM's processing has stalled.
    static let hrrrMaxRunAge: TimeInterval = 6 * 3600

    let http: HTTPClient

    public init(http: HTTPClient = HTTPClient(timeout: 15)) {
        self.http = http
    }

    /// Picks NOAA over the contiguous U.S. (where both the NEXRAD mosaic and the HRRR forecast exist)
    /// and RainViewer elsewhere when the preference is automatic.
    public static func resolve(_ preference: RadarSourcePreference, latitude: Double, longitude: Double) -> RadarSource {
        switch preference {
        case .noaa: return .noaa
        case .rainViewer: return .rainViewer
        case .automatic:
            return GeoMath.isInContiguousUnitedStates(latitude: latitude, longitude: longitude) ? .noaa : .rainViewer
        }
    }

    public func timeline(for source: RadarSource, now: Date = Date()) async throws -> RadarTimeline {
        switch source {
        case .rainViewer:
            let data = try await http.data(from: Self.rainViewerMapsURL)
            return try Self.parseRainViewer(data, now: now)
        case .noaa:
            async let radarMetadata = optionalData(from: Self.noaaLatestMetadataURL)
            async let hrrrMetadata = optionalData(from: Self.hrrrMetadataURL)
            let latest = await radarMetadata.flatMap(Self.parseNOAAValidTime)
            let runTime = await hrrrMetadata.flatMap(Self.parseHRRRRunTime)
            return Self.noaaTimeline(latestValidTime: latest, hrrrRunTime: runTime, now: now)
        }
    }

    private func optionalData(from url: URL) async -> Data? {
        try? await http.data(from: url)
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
                // 256-pixel tiles: the free tier stops at zoom 7, so 512-pixel tiles would only cost
                // four times the memory per frame. Universal Blue (2), smoothed, with snow colors (1_1).
                tileURLTemplate: "\(host)\(item.path)/256/{z}/{x}/{y}/2/1_1.png",
                maxNativeZoom: 7,
                isForecast: forecast
            )
        }
        let past = maps.radar?.past?.map { frame($0, forecast: false) } ?? []
        // RainViewer stopped publishing nowcast frames on January 1, 2026; kept in case a paid key returns them.
        let nowcast = maps.radar?.nowcast?.map { frame($0, forecast: true) } ?? []
        guard !past.isEmpty || !nowcast.isEmpty else { throw WeatherServiceError.noData }
        return RadarTimeline(source: .rainViewer, frames: past + nowcast, fetchedAt: now)
    }

    // MARK: NOAA (Iowa Environmental Mesonet tile cache)

    /// The past 50 minutes of the NEXRAD mosaic, each frame named by its own UTC time
    /// (`ridge::USCOMP-N0Q-YYYYMMDDHHMI`), followed by HRRR forecast frames when a recent run is known.
    static func noaaTimeline(latestValidTime: Date?, hrrrRunTime: Date? = nil, now: Date) -> RadarTimeline {
        let latest = latestValidTime ?? estimatedNOAAValidTime(now: now)
        var frames = stride(from: pastMinutes, through: 0, by: -5).map { minutesAgo -> RadarFrame in
            let time = latest.addingTimeInterval(-Double(minutesAgo) * 60)
            let stamp = utcStamp(time)
            return RadarFrame(
                id: "noaa-\(stamp)",
                time: time,
                // `/c/` serves timestamped layers with a 14-day cache header.
                tileURLTemplate: "\(iemHost)/c/tile.py/1.0.0/ridge::USCOMP-N0Q-\(stamp)/{z}/{x}/{y}.png",
                maxNativeZoom: 10,
                hostShards: iemShards
            )
        }
        var runTime: Date?
        if let hrrrRunTime {
            let forecast = hrrrForecastFrames(runTime: hrrrRunTime, after: latest)
            if !forecast.isEmpty {
                frames += forecast
                runTime = hrrrRunTime
            }
        }
        return RadarTimeline(source: .noaa, frames: frames, fetchedAt: now, forecastRunTime: runTime)
    }

    /// HRRR forecast reflectivity every 15 minutes after the latest radar frame, out to
    /// `horizonMinutes` after it. Layer `hrrr::REFD-F<minutes, 4 digits>-<run, YYYYMMDDHHMI UTC>`.
    static func hrrrForecastFrames(runTime: Date, after latestObserved: Date, horizonMinutes: Int = forecastHorizonMinutes) -> [RadarFrame] {
        guard latestObserved.timeIntervalSince(runTime) <= hrrrMaxRunAge else { return [] }
        let step = Double(forecastStepMinutes * 60)
        let start = ((latestObserved.timeIntervalSince1970 / step).rounded(.down) + 1) * step
        let end = latestObserved.timeIntervalSince1970 + Double(horizonMinutes * 60)
        let runStamp = utcStamp(runTime)
        var frames: [RadarFrame] = []
        var valid = start
        while valid <= end {
            let leadSeconds = valid - runTime.timeIntervalSince1970
            let lead = Int((leadSeconds / 60).rounded())
            if leadSeconds >= 0, lead <= hrrrMaxLeadMinutes, lead % forecastStepMinutes == 0 {
                let leadText = String(format: "%04d", lead)
                let layer = "hrrr::REFD-F\(leadText)-\(runStamp)"
                frames.append(RadarFrame(
                    id: "hrrr-\(runStamp)-F\(leadText)",
                    time: Date(timeIntervalSince1970: valid),
                    // The IEM documents HRRR tiles under `/cache/`; the run time in the layer name keeps
                    // the URL's content fixed.
                    tileURLTemplate: "\(iemHost)/cache/tile.py/1.0.0/\(layer)/{z}/{x}/{y}.png",
                    // HRRR imagery is 0.02° (about 2 km); zoom 8 tiles already oversample it.
                    maxNativeZoom: 8,
                    isForecast: true,
                    hostShards: iemShards
                ))
            }
            valid += step
        }
        return frames
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

    /// `{"model_init_utc": "2026-10-01T21:00:00Z", "forecast_minute": 1080.0, ...}`
    static func parseHRRRRunTime(_ data: Data) -> Date? {
        struct Metadata: Decodable {
            let modelInitUTC: String?
            enum CodingKeys: String, CodingKey { case modelInitUTC = "model_init_utc" }
        }
        guard let value = (try? JSONDecoder().decode(Metadata.self, from: data))?.modelInitUTC else { return nil }
        return NWSAlertsClient.parseDate(value)
    }

    /// `YYYYMMDDHHMI` in UTC, the IEM's layer timestamp format.
    static func utcStamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d%02d%02d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
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
