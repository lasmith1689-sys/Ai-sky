import Foundation
import XCTest
@testable import AiSkyKit

final class LocationLibraryTests: XCTestCase {
    func place(_ index: Int) -> SavedLocation {
        SavedLocation(placeName: "Place \(index)", latitude: Double(index), longitude: Double(index))
    }

    func testLibraryHoldsTwentyLocations() throws {
        var list: [SavedLocation] = []
        for index in 0..<20 {
            list = try LocationLibrary.adding(place(index), to: list)
        }
        XCTAssertEqual(list.count, 20)
        XCTAssertFalse(LocationLibrary.canAdd(to: list))
        XCTAssertEqual(LocationLibrary.remainingSlots(in: list), 0)
        XCTAssertThrowsError(try LocationLibrary.adding(place(21), to: list)) { error in
            XCTAssertEqual(error as? LocationLibraryError, .limitReached(20))
        }
    }

    func testDuplicatesAreRejected() throws {
        let chicago = SavedLocation(placeName: "Chicago", latitude: 41.8781, longitude: -87.6298)
        let list = try LocationLibrary.adding(chicago, to: [])
        let nearby = SavedLocation(placeName: "The Loop", latitude: 41.8786, longitude: -87.6251)
        XCTAssertThrowsError(try LocationLibrary.adding(nearby, to: list)) { error in
            XCTAssertEqual(error as? LocationLibraryError, .duplicate("Chicago"))
        }
    }

    func testMoveMatchesSwiftUISemantics() {
        let list = (0..<5).map(place)
        let movedDown = LocationLibrary.moving(list, fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(movedDown.map(\.placeName), ["Place 1", "Place 2", "Place 0", "Place 3", "Place 4"])
        let movedUp = LocationLibrary.moving(list, fromOffsets: IndexSet(integer: 4), toOffset: 1)
        XCTAssertEqual(movedUp.map(\.placeName), ["Place 0", "Place 4", "Place 1", "Place 2", "Place 3"])
        let toEnd = LocationLibrary.moving(list, fromOffsets: IndexSet([0, 2]), toOffset: 5)
        XCTAssertEqual(toEnd.map(\.placeName), ["Place 1", "Place 3", "Place 4", "Place 0", "Place 2"])
    }

    func testRenameAndClearNickname() {
        let list = [place(1)]
        let renamed = LocationLibrary.renaming(id: list[0].id, to: "  Home ", in: list)
        XCTAssertEqual(renamed[0].displayName, "Home")
        XCTAssertEqual(renamed[0].displaySubtitle, "Place 1")
        let cleared = LocationLibrary.renaming(id: list[0].id, to: "", in: renamed)
        XCTAssertNil(cleared[0].customName)
        XCTAssertEqual(cleared[0].displayName, "Place 1")
    }

    func testSharedStorePersistsLibraryAndSettings() throws {
        let suite = "aisky-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SharedStore(defaults: defaults, cachesDirectory: FileManager.default.temporaryDirectory)

        XCTAssertTrue(store.loadSavedLocations().isEmpty)
        store.saveSavedLocations(SampleData.savedLocations)
        XCTAssertEqual(store.loadSavedLocations(), SampleData.savedLocations)

        var settings = AppSettings(units: .metric)
        settings.rainAlertsEnabled = true
        store.saveSettings(settings)
        XCTAssertEqual(store.loadSettings(), settings)

        store.saveCurrentLocation(CurrentLocationSnapshot(latitude: 1, longitude: 2, name: "Here"))
        let all = store.loadAllWeatherLocations()
        XCTAssertEqual(all.first?.id, WeatherLocation.currentLocationID)
        XCTAssertEqual(all.count, SampleData.savedLocations.count + 1)
        XCTAssertEqual(store.weatherLocation(id: SampleData.savedLocations[1].id.uuidString)?.name, "Work")
    }

    func testSettingsDecodeWithMissingKeys() throws {
        let json = #"{"units":{"temperature":"celsius","windSpeed":"kmh","precipitation":"millimeters","pressure":"hectopascals","distance":"kilometers"}}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.units, .metric)
        XCTAssertEqual(settings.dataSource, .automatic)
        XCTAssertEqual(settings.radarOpacity, 0.75, accuracy: 0.0001)
    }

    func testSnapshotCacheRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aisky-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SnapshotCache(directory: directory)
        let snapshot = SampleData.snapshot(now: Fixtures.now)
        await cache.store(snapshot)

        let reloaded = SnapshotCache(directory: directory)
        let restored = await reloaded.snapshot(for: snapshot.location.id)
        XCTAssertEqual(restored, snapshot)
        let summary = await reloaded.summary(for: snapshot.location.id)
        XCTAssertEqual(summary?.temperature, snapshot.current.temperature)

        // An older summary must not replace a newer one.
        var older = snapshot.summary
        older.fetchedAt = Fixtures.now.addingTimeInterval(-3600)
        older.temperature = -40
        await reloaded.store(summaries: [older])
        let kept = await reloaded.summary(for: snapshot.location.id)
        XCTAssertEqual(kept?.temperature, snapshot.current.temperature)
    }
}

final class UnitsTests: XCTestCase {
    func testTemperatureFormatting() {
        XCTAssertEqual(Fixtures.imperial.temperature(22.4), "72°")
        XCTAssertEqual(Fixtures.imperial.temperature(22.4, includeUnit: true), "72°F")
        XCTAssertEqual(Fixtures.metric.temperature(-0.3), "0°")
        XCTAssertEqual(Fixtures.metric.temperature(-12.6), "-13°")
    }

    func testWind() {
        XCTAssertEqual(Fixtures.imperial.wind(speed: 16.1, direction: 315), "10 mph NW")
        XCTAssertEqual(Fixtures.metric.wind(speed: 0.4, direction: 90), "Calm")
        XCTAssertEqual(WindSpeedUnit.beaufortNumber(kmh: 30), 5)
        XCTAssertEqual(WeatherFormatter.compassDirection(359), "N")
        XCTAssertEqual(WeatherFormatter.compassDirection(-45), "NW")
    }

    func testPrecipitation() {
        XCTAssertEqual(Fixtures.imperial.precipitation(10.668), "0.42 in")
        XCTAssertEqual(Fixtures.imperial.precipitation(0.05), "<0.01 in")
        XCTAssertEqual(Fixtures.imperial.precipitation(0), "0.00 in")
        XCTAssertEqual(Fixtures.metric.precipitation(10.66), "10.7 mm")
        XCTAssertEqual(Fixtures.imperial.snowfall(12.7), "5.0 in")
        XCTAssertEqual(Fixtures.metric.snowfall(12.7), "13 cm")
    }

    func testPressureAndVisibility() {
        XCTAssertEqual(Fixtures.imperial.pressure(1016.9), "30.03 inHg")
        XCTAssertEqual(Fixtures.metric.pressure(1016.9), "1017 hPa")
        XCTAssertEqual(Fixtures.imperial.visibility(24.14), "15 mi")
        XCTAssertEqual(Fixtures.metric.visibility(4.2), "4.2 km")
    }

    func testChanceRounding() {
        XCTAssertEqual(Fixtures.imperial.chance(0.34), "30%")
        XCTAssertEqual(Fixtures.imperial.chance(0.35), "40%")
    }

    func testRegionalDefaults() {
        XCTAssertEqual(UnitPreferences.defaults(for: Locale(identifier: "en_US")), .imperial)
        XCTAssertEqual(UnitPreferences.defaults(for: Locale(identifier: "en_GB")), .uk)
        XCTAssertEqual(UnitPreferences.defaults(for: Locale(identifier: "de_DE")), .metric)
    }

    func testHourFormattingUsesLocationTimeZone() {
        let date = Fixtures.now // 17:20Z
        XCTAssertEqual(Fixtures.imperial.hour(date, timeZone: Fixtures.chicago).normalizedSpaces, "12 PM")
        XCTAssertEqual(Fixtures.imperial.time(date, timeZone: TimeZone(identifier: "Europe/London")!).normalizedSpaces, "6:20 PM")
        XCTAssertEqual(Fixtures.imperial.dayLabel(date, timeZone: Fixtures.chicago, now: date), "Today")
    }
}

final class AlertsAndRadarTests: XCTestCase {
    func testNWSParsing() throws {
        let alerts = try NWSAlertsClient.parse(Fixtures.data("nws-alerts"), now: Fixtures.now)
        // The expired statement is filtered out; the warning sorts first.
        XCTAssertEqual(alerts.map(\.title), ["Severe Thunderstorm Warning", "Wind Advisory"])
        XCTAssertEqual(alerts[0].severity, .severe)
        let advisory = alerts[1]
        XCTAssertEqual(advisory.details, "* WHAT...Southwest winds 20 to 30 mph with gusts up to 50 mph expected.\n\n* WHERE...Cook and DuPage Counties.")
        XCTAssertNotNil(advisory.expires)
        XCTAssertEqual(advisory.detailsURL?.host, "api.weather.gov")
    }

    func testNWSURLUsesFourDecimals() {
        let url = NWSAlertsClient.alertsURL(latitude: 41.878113, longitude: -87.629799)
        XCTAssertEqual(url.absoluteString, "https://api.weather.gov/alerts/active?point=41.8781,-87.6298")
    }

    func testRainViewerParsing() throws {
        let timeline = try RadarService.parseRainViewer(Fixtures.data("rainviewer"), now: Fixtures.now)
        XCTAssertEqual(timeline.frames.count, 13)
        XCTAssertEqual(timeline.source, .rainViewer)
        XCTAssertTrue(timeline.frames.first!.time < timeline.frames.last!.time)
        let url = timeline.frames.last!.tileURL(z: 5, x: 8, y: 11, highResolution: true)
        XCTAssertEqual(url?.absoluteString.hasPrefix("https://tilecache.rainviewer.com/v2/radar/"), true)
        XCTAssertEqual(url?.absoluteString.hasSuffix("/512/5/8/11/2/1_1.png"), true)
        XCTAssertEqual(timeline.frames.last!.maxNativeZoom, 7)
    }

    func testNOAATimeline() {
        let timeline = RadarService.noaaTimeline(latestValidTime: nil, now: Fixtures.now)
        XCTAssertEqual(timeline.frames.count, 11)
        XCTAssertEqual(timeline.frames.last?.tileURLTemplate, "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913/{z}/{x}/{y}.png")
        XCTAssertEqual(timeline.frames.first?.tileURLTemplate, "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913-m50m/{z}/{x}/{y}.png")
        XCTAssertEqual(timeline.frames[1].time.timeIntervalSince(timeline.frames[0].time), 300)
        XCTAssertLessThan(timeline.frames.last!.time, Fixtures.now)
        let metadata = Data(#"{"meta": {"valid": "2026-09-28T17:10:00Z", "product": "n0q"}}"#.utf8)
        XCTAssertEqual(RadarService.parseNOAAValidTime(metadata), Date(timeIntervalSince1970: 1_790_615_400))
    }

    func testRadarSourceResolution() {
        XCTAssertEqual(RadarService.resolve(.automatic, latitude: 41.9, longitude: -87.6), .noaa)
        XCTAssertEqual(RadarService.resolve(.automatic, latitude: 51.5, longitude: -0.1), .rainViewer)
        XCTAssertEqual(RadarService.resolve(.rainViewer, latitude: 41.9, longitude: -87.6), .rainViewer)
    }
}
