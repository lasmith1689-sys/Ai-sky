import Foundation
import XCTest
@testable import AiSkyKit

/// Audit of PR #1 (docs/hq/pr1-audit.md), risk R1: the Apple Weather pause is stamped with the
/// wall clock, so a failure dated in the future (the device clock moved backwards after it was
/// recorded) must not keep Apple Weather paused for longer than the 15-minute backoff.
final class WeatherKitPauseAuditTests: XCTestCase {
    let now = Fixtures.now
    var directory: URL!
    var suite: String!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("aisky-pause-\(UUID().uuidString)")
        suite = "aisky-pause-\(UUID().uuidString)"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    #if canImport(WeatherKit)
    func testPauseEndsWhenTheClockMovedBackwards() throws {
        let store = SharedStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)), cachesDirectory: directory)
        let app = WeatherRepository(cache: SnapshotCache(directory: directory), store: store, weatherKitAvailable: true)
        let settings = AppSettings(units: .metric)

        // A failure recorded 5 minutes ago still pauses Apple Weather.
        store.set(WeatherRepository.WeatherKitFailure(date: now.addingTimeInterval(-5 * 60), message: "test"), forKey: .weatherKitFailure)
        XCTAssertFalse(app.shouldUseWeatherKit(settings, now: now))

        // The failure was stamped an hour "ahead" of the clock: the clock has since moved back.
        store.set(WeatherRepository.WeatherKitFailure(date: now.addingTimeInterval(60 * 60), message: "test"), forKey: .weatherKitFailure)
        XCTAssertTrue(app.shouldUseWeatherKit(settings, now: now), "a future-dated failure keeps Apple Weather paused until the clock catches up")
    }
    #endif
}
