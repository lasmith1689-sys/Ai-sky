import Foundation

/// On-disk + in-memory cache of weather snapshots, shared by the app and widgets.
public actor SnapshotCache {
    public static let shared = SnapshotCache(directory: SharedStore.shared.cachesDirectory.appendingPathComponent("Weather", isDirectory: true))

    private let directory: URL
    private var memory: [String: WeatherSnapshot] = [:]
    private var summaries: [String: LocationWeatherSummary]?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directory: URL) {
        self.directory = directory
    }

    public func snapshot(for locationID: String) -> WeatherSnapshot? {
        if let cached = memory[locationID] { return cached }
        guard let data = try? Data(contentsOf: fileURL(for: locationID)),
              let snapshot = try? decoder.decode(WeatherSnapshot.self, from: data) else {
            return nil
        }
        memory[locationID] = snapshot
        return snapshot
    }

    public func store(_ snapshot: WeatherSnapshot) {
        memory[snapshot.location.id] = snapshot
        ensureDirectory()
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: fileURL(for: snapshot.location.id), options: .atomic)
        }
        var all = loadSummaries()
        all[snapshot.location.id] = snapshot.summary
        saveSummaries(all)
    }

    public func remove(locationID: String) {
        memory[locationID] = nil
        try? FileManager.default.removeItem(at: fileURL(for: locationID))
        var all = loadSummaries()
        all[locationID] = nil
        saveSummaries(all)
    }

    // MARK: Summaries (library list / multi-location widget)

    public func summary(for locationID: String) -> LocationWeatherSummary? {
        loadSummaries()[locationID]
    }

    public func allSummaries() -> [String: LocationWeatherSummary] {
        loadSummaries()
    }

    public func store(summaries newSummaries: [LocationWeatherSummary]) {
        var all = loadSummaries()
        for summary in newSummaries {
            // Never replace a newer entry (e.g. from a full snapshot) with an older one.
            if let existing = all[summary.locationID], existing.fetchedAt > summary.fetchedAt { continue }
            all[summary.locationID] = summary
        }
        saveSummaries(all)
    }

    // MARK: Private

    private func loadSummaries() -> [String: LocationWeatherSummary] {
        if let summaries { return summaries }
        let loaded = (try? Data(contentsOf: summariesURL))
            .flatMap { try? decoder.decode([String: LocationWeatherSummary].self, from: $0) } ?? [:]
        summaries = loaded
        return loaded
    }

    private func saveSummaries(_ value: [String: LocationWeatherSummary]) {
        summaries = value
        ensureDirectory()
        if let data = try? encoder.encode(value) {
            try? data.write(to: summariesURL, options: .atomic)
        }
    }

    private var summariesURL: URL { directory.appendingPathComponent("summaries.json") }

    private func fileURL(for locationID: String) -> URL {
        let safe = locationID.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        return directory.appendingPathComponent("snapshot-\(String(safe)).json")
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
