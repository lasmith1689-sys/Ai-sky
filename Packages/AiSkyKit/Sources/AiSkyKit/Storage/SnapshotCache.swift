import Foundation

/// On-disk + in-memory cache of weather snapshots, shared by the app and widgets.
///
/// The app and the widget extension are separate processes, each with its own instance over the
/// same App Group directory, so disk is the source of truth. Each in-memory copy remembers which
/// version of its file it matches, and is replaced by the file whenever another process has
/// written a newer one.
public actor SnapshotCache {
    public static let shared = SnapshotCache(directory: SharedStore.shared.cachesDirectory.appendingPathComponent("Weather", isDirectory: true))

    /// One version of a file on disk. Writes are atomic (a temporary file renamed over the old
    /// one), so each write changes the file number as well as the modification date.
    private struct DiskVersion: Equatable {
        var modified: Date?
        var fileNumber: UInt64?
    }

    private struct Cached<Value> {
        var value: Value
        /// The file's version when `value` was read or written; nil if there was no file.
        var version: DiskVersion?
    }

    private let directory: URL
    private var memory: [String: Cached<WeatherSnapshot>] = [:]
    private var summaries: Cached<[String: LocationWeatherSummary]>?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directory: URL) {
        self.directory = directory
    }

    public func snapshot(for locationID: String) -> WeatherSnapshot? {
        let url = fileURL(for: locationID)
        let onDisk = diskVersion(of: url)
        // Without a file there is nothing newer to read, so the memory copy (if any) stands.
        if let cached = memory[locationID], onDisk == nil || cached.version == onDisk {
            return cached.value
        }
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? decoder.decode(WeatherSnapshot.self, from: data) else {
            return memory[locationID]?.value
        }
        memory[locationID] = Cached(value: snapshot, version: onDisk)
        return snapshot
    }

    public func store(_ snapshot: WeatherSnapshot) {
        let locationID = snapshot.location.id
        let url = fileURL(for: locationID)
        ensureDirectory()
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
        // Recorded even if the write failed: the memory copy then stands until the file changes.
        memory[locationID] = Cached(value: snapshot, version: diskVersion(of: url))
        updateSummaries { $0[locationID] = snapshot.summary }
    }

    public func remove(locationID: String) {
        memory[locationID] = nil
        try? FileManager.default.removeItem(at: fileURL(for: locationID))
        updateSummaries { $0[locationID] = nil }
    }

    // MARK: Summaries (library list / multi-location widget)

    public func summary(for locationID: String) -> LocationWeatherSummary? {
        loadSummaries()[locationID]
    }

    public func allSummaries() -> [String: LocationWeatherSummary] {
        loadSummaries()
    }

    public func store(summaries newSummaries: [LocationWeatherSummary]) {
        updateSummaries { all in
            for summary in newSummaries {
                // Never replace a newer entry (e.g. from a full snapshot) with an older one.
                if let existing = all[summary.locationID], existing.fetchedAt > summary.fetchedAt { continue }
                all[summary.locationID] = summary
            }
        }
    }

    // MARK: Private

    /// The summaries as currently on disk, re-read whenever another process has rewritten the file.
    private func loadSummaries() -> [String: LocationWeatherSummary] {
        let onDisk = diskVersion(of: summariesURL)
        if let summaries, onDisk == nil || summaries.version == onDisk {
            return summaries.value
        }
        let loaded = (try? Data(contentsOf: summariesURL))
            .flatMap { try? decoder.decode([String: LocationWeatherSummary].self, from: $0) } ?? [:]
        summaries = Cached(value: loaded, version: onDisk)
        return loaded
    }

    /// Applies `change` to the latest summaries on disk and writes them back atomically, so entries
    /// the other process stored since this one last looked are kept. Only the keys `change` touches
    /// are this process's to decide.
    private func updateSummaries(_ change: (inout [String: LocationWeatherSummary]) -> Void) {
        var all = loadSummaries()
        change(&all)
        ensureDirectory()
        if let data = try? encoder.encode(all) {
            try? data.write(to: summariesURL, options: .atomic)
        }
        summaries = Cached(value: all, version: diskVersion(of: summariesURL))
    }

    private func diskVersion(of url: URL) -> DiskVersion? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return DiskVersion(
            modified: attributes[.modificationDate] as? Date,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        )
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
