import Foundation
import XCTest
@testable import AiSkyKit

/// Audit of PR #1 (docs/hq/pr1-audit.md). The app and the widget extension are separate processes,
/// each with its own `SnapshotCache.shared` over the same App Group directory. Two caches over one
/// directory model that. These tests are expected to FAIL on the audited code: they pin down
/// bugs B1 and B2 and are not fixes.
final class SharedCacheAuditTests: XCTestCase {
    let now = Fixtures.now
    var directory: URL!
    var suite: String!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("aisky-audit-\(UUID().uuidString)")
        suite = "aisky-audit-\(UUID().uuidString)"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    func snapshot(_ source: WeatherDataSource, age: TimeInterval) -> WeatherSnapshot {
        var snapshot = SampleData.snapshot(now: now.addingTimeInterval(-age))
        snapshot.source = source
        return snapshot
    }

    /// B1: a cache that has read or written a location once keeps serving its in-memory copy and
    /// never sees a newer snapshot the other process wrote to disk, so the widget ignores the
    /// app's fresh Apple Weather forecast.
    func testWidgetSeesTheAppsNewerSnapshot() async throws {
        let widgetCache = SnapshotCache(directory: directory)
        let appCache = SnapshotCache(directory: directory)
        let store = SharedStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)), cachesDirectory: directory)
        let widget = WeatherRepository(cache: widgetCache, store: store, weatherKitAvailable: false)

        // The widget fetched Open-Meteo 25 minutes ago; the app has since stored Apple Weather.
        await widgetCache.store(snapshot(.openMeteo, age: 25 * 60))
        let fresh = snapshot(.appleWeather, age: 60)
        await appCache.store(fresh)

        let served = await widget.cachedSnapshot(for: fresh.location)
        XCTAssertEqual(served?.source, .appleWeather)
        XCTAssertEqual(served, fresh)
        XCTAssertTrue(widget.canReuse(try XCTUnwrap(served), settings: AppSettings(units: .metric), maxAge: 20 * 60, now: now))
    }

    /// B2: summaries.json is read once per process and then rewritten from memory, so a summary
    /// the other process stored in between is dropped from disk.
    func testSummaryStoredByTheOtherProcessSurvivesALaterWrite() async throws {
        let appCache = SnapshotCache(directory: directory)
        _ = await appCache.allSummaries() // the app has already shown its library list

        let widgetCache = SnapshotCache(directory: directory)
        var elsewhere = snapshot(.openMeteo, age: 60)
        elsewhere.location.id = "audit-other-place"
        await widgetCache.store(elsewhere)

        await appCache.store(snapshot(.appleWeather, age: 60))

        let onDisk = await SnapshotCache(directory: directory).allSummaries()
        XCTAssertNotNil(onDisk[SampleData.location.id])
        XCTAssertNotNil(onDisk["audit-other-place"], "the widget's summary was overwritten by the app's stale in-memory copy")
    }
}
