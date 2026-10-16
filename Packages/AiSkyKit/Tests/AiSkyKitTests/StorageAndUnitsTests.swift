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
        let url = timeline.frames.last!.tileURL(z: 5, x: 8, y: 11)
        XCTAssertEqual(url?.absoluteString.hasPrefix("https://tilecache.rainviewer.com/v2/radar/"), true)
        XCTAssertEqual(url?.absoluteString.hasSuffix("/256/5/8/11/2/1_1.png"), true)
        XCTAssertEqual(timeline.frames.last!.maxNativeZoom, 7)
        XCTAssertFalse(timeline.hasForecast)
        XCTAssertEqual(timeline.latestObservedIndex, 12)
    }

    func testNOAATimelineNamesEachFrameByItsTime() {
        // No metadata: the mosaic is assumed 5 to 10 minutes behind (17:20Z → 17:15Z).
        let timeline = RadarService.noaaTimeline(latestValidTime: nil, now: Fixtures.now)
        XCTAssertEqual(timeline.frames.count, 11)
        XCTAssertFalse(timeline.hasForecast)
        XCTAssertNil(timeline.forecastRunTime)
        XCTAssertEqual(timeline.frames.last?.time, Date(timeIntervalSince1970: 1_790_615_700))
        XCTAssertEqual(timeline.frames.last?.tileURLTemplate, "https://mesonet{s}.agron.iastate.edu/c/tile.py/1.0.0/ridge::USCOMP-N0Q-202609281715/{z}/{x}/{y}.png")
        XCTAssertEqual(timeline.frames.first?.tileURLTemplate, "https://mesonet{s}.agron.iastate.edu/c/tile.py/1.0.0/ridge::USCOMP-N0Q-202609281625/{z}/{x}/{y}.png")
        XCTAssertEqual(timeline.frames[1].time.timeIntervalSince(timeline.frames[0].time), 300)
        XCTAssertLessThan(timeline.frames.last!.time, Fixtures.now)
        XCTAssertEqual(timeline.latestObservedIndex, 10)

        let metadata = Data(#"{"meta": {"valid": "2026-09-28T17:10:00Z", "product": "n0q"}}"#.utf8)
        XCTAssertEqual(RadarService.parseNOAAValidTime(metadata), Date(timeIntervalSince1970: 1_790_615_400))
    }

    func testNOAAFramesKeepTheirIDsAcrossRefreshes() {
        // Five minutes later the timeline gains one frame and drops one; the other ten (and their
        // cached tiles) are the same frames.
        let earlier = RadarService.noaaTimeline(latestValidTime: Date(timeIntervalSince1970: 1_790_615_400), now: Fixtures.now)
        let later = RadarService.noaaTimeline(latestValidTime: Date(timeIntervalSince1970: 1_790_615_700), now: Fixtures.now)
        XCTAssertEqual(Array(earlier.frames.dropFirst()), Array(later.frames.dropLast()))
        XCTAssertEqual(later.frames.last?.id, "noaa-202609281715")
    }

    func testTileHostShards() {
        let frame = RadarService.noaaTimeline(latestValidTime: Date(timeIntervalSince1970: 1_790_615_400), now: Fixtures.now).frames.last!
        XCTAssertEqual(frame.tileURL(z: 5, x: 8, y: 11)?.absoluteString, "https://mesonet3.agron.iastate.edu/c/tile.py/1.0.0/ridge::USCOMP-N0Q-202609281710/5/8/11.png")
        XCTAssertEqual(frame.tileURL(z: 5, x: 8, y: 12)?.absoluteString, "https://mesonet.agron.iastate.edu/c/tile.py/1.0.0/ridge::USCOMP-N0Q-202609281710/5/8/12.png")
        XCTAssertEqual(frame.tileURL(for: RadarTileKey(z: 5, x: 9, y: 12))?.host, "mesonet1.agron.iastate.edu")
    }

    func testHRRRForecastFramesFollowTheLatestRadar() throws {
        let runTime = try XCTUnwrap(RadarService.parseHRRRRunTime(Data(#"{"model_init_utc": "2026-09-28T15:00:00Z", "forecast_minute": 1080.0, "model_forecast_utc": "2026-09-29T09:00:00Z"}"#.utf8)))
        XCTAssertEqual(runTime, Date(timeIntervalSince1970: 1_790_607_600))
        let latest = Date(timeIntervalSince1970: 1_790_615_400) // 17:10Z
        let timeline = RadarService.noaaTimeline(latestValidTime: latest, hrrrRunTime: runTime, now: Fixtures.now)
        XCTAssertEqual(timeline.frames.count, 11 + 8)
        XCTAssertTrue(timeline.hasForecast)
        XCTAssertEqual(timeline.forecastRunTime, runTime)
        XCTAssertEqual(timeline.latestObservedIndex, 10)
        XCTAssertEqual(timeline.frames[10].time, latest)

        let forecast = timeline.frames.filter(\.isForecast)
        // Every 15 minutes from the next quarter hour (17:15Z) through 2 hours after the radar (19:00Z).
        XCTAssertEqual(forecast.first?.time, Date(timeIntervalSince1970: 1_790_615_700))
        XCTAssertEqual(forecast.last?.time, Date(timeIntervalSince1970: 1_790_622_000))
        XCTAssertEqual(zip(forecast, forecast.dropFirst()).map { $1.time.timeIntervalSince($0.time) }, Array(repeating: 900, count: 7))
        XCTAssertEqual(forecast.first?.tileURLTemplate, "https://mesonet{s}.agron.iastate.edu/cache/tile.py/1.0.0/hrrr::REFD-F0135-202609281500/{z}/{x}/{y}.png")
        XCTAssertEqual(forecast.last?.tileURLTemplate, "https://mesonet{s}.agron.iastate.edu/cache/tile.py/1.0.0/hrrr::REFD-F0240-202609281500/{z}/{x}/{y}.png")
        XCTAssertEqual(forecast.first?.id, "hrrr-202609281500-F0135")
        XCTAssertEqual(forecast.first?.maxNativeZoom, 8)
        XCTAssertTrue(forecast.allSatisfy { $0.time > latest })
    }

    func testHRRRForecastStartsAfterAQuarterHourRadar() {
        let runTime = Date(timeIntervalSince1970: 1_790_607_600) // 15:00Z
        let latest = Date(timeIntervalSince1970: 1_790_615_700) // 17:15Z, itself a quarter hour
        let frames = RadarService.hrrrForecastFrames(runTime: runTime, after: latest)
        XCTAssertEqual(frames.first?.time, Date(timeIntervalSince1970: 1_790_616_600)) // 17:30Z
        XCTAssertEqual(frames.last?.time, Date(timeIntervalSince1970: 1_790_622_900)) // 19:15Z
        XCTAssertEqual(frames.count, 8)
    }

    func testStaleOrMissingHRRRRunLeavesRadarOnly() {
        let latest = Date(timeIntervalSince1970: 1_790_615_400) // 17:10Z
        let oldRun = Date(timeIntervalSince1970: 1_790_589_600) // 10:00Z, over 6 hours earlier
        XCTAssertTrue(RadarService.hrrrForecastFrames(runTime: oldRun, after: latest).isEmpty)
        let timeline = RadarService.noaaTimeline(latestValidTime: latest, hrrrRunTime: oldRun, now: Fixtures.now)
        XCTAssertEqual(timeline.frames.count, 11)
        XCTAssertNil(timeline.forecastRunTime)
        XCTAssertNil(RadarService.parseHRRRRunTime(Data("{}".utf8)))
        XCTAssertNil(RadarService.parseHRRRRunTime(Data("not json".utf8)))
    }

    func testRadarSourceResolution() {
        XCTAssertEqual(RadarService.resolve(.automatic, latitude: 41.9, longitude: -87.6), .noaa)
        XCTAssertEqual(RadarService.resolve(.automatic, latitude: 51.5, longitude: -0.1), .rainViewer)
        XCTAssertEqual(RadarService.resolve(.rainViewer, latitude: 41.9, longitude: -87.6), .rainViewer)
        // The NEXRAD mosaic and the HRRR cover the contiguous U.S. only; Honolulu gets RainViewer.
        XCTAssertEqual(RadarService.resolve(.automatic, latitude: 21.3, longitude: -157.9), .rainViewer)
        XCTAssertEqual(RadarService.resolve(.automatic, latitude: 40.81, longitude: -74.21), .noaa)
    }
}

final class RadarTilingTests: XCTestCase {
    func testZoomLevelFromZoomScale() {
        XCTAssertEqual(RadarTiling.zoomLevel(forZoomScale: 1), 20)
        XCTAssertEqual(RadarTiling.zoomLevel(forZoomScale: pow(2, -13)), 7)
        XCTAssertEqual(RadarTiling.zoomLevel(forZoomScale: pow(2, -13) * 1.3), 7)
        XCTAssertEqual(RadarTiling.zoomLevel(forZoomScale: pow(2, -13) * 1.6), 8)
        XCTAssertEqual(RadarTiling.zoomLevel(forZoomScale: 0), 0)
        XCTAssertEqual(RadarTiling.zoomLevel(forZoomScale: .infinity), 0)
    }

    func testTileRectsTileTheWorld() {
        let world = RadarTiling.worldSize
        let tile = RadarTiling.rect(for: RadarTileKey(z: 1, x: 1, y: 0))
        XCTAssertEqual(tile.x, world / 2)
        XCTAssertEqual(tile.y, 0)
        XCTAssertEqual(tile.size, world / 2)
        XCTAssertEqual(RadarTiling.rect(for: RadarTileKey(z: 0, x: 0, y: 0)).size, world)
    }

    func testKeysCoveringARect() {
        let half = RadarTiling.worldSize / 2
        // The far edge is exclusive: a rectangle ending exactly on a tile border doesn't reach the next tile.
        XCTAssertEqual(RadarTiling.keys(minX: 0, minY: 0, maxX: half, maxY: half, zoom: 1), [RadarTileKey(z: 1, x: 0, y: 0)])
        XCTAssertEqual(
            RadarTiling.keys(minX: half - 1, minY: half - 1, maxX: half + 1, maxY: half + 1, zoom: 1),
            [RadarTileKey(z: 1, x: 0, y: 0), RadarTileKey(z: 1, x: 1, y: 0), RadarTileKey(z: 1, x: 0, y: 1), RadarTileKey(z: 1, x: 1, y: 1)]
        )
        // Outside the world is ignored.
        XCTAssertEqual(RadarTiling.keys(minX: -10, minY: -10, maxX: 1, maxY: 1, zoom: 2), [RadarTileKey(z: 2, x: 0, y: 0)])
        XCTAssertTrue(RadarTiling.keys(minX: 5, minY: 5, maxX: 5, maxY: 9, zoom: 3).isEmpty)
    }

    func testChicagoTileAndItsAncestors() {
        let chicago = RadarTiling.key(latitude: 41.8781, longitude: -87.6298, zoom: 10)
        XCTAssertEqual(chicago, RadarTileKey(z: 10, x: 262, y: 380))
        XCTAssertEqual(chicago.ancestor(levels: 3), RadarTiling.key(latitude: 41.8781, longitude: -87.6298, zoom: 7))
        XCTAssertEqual(chicago.ancestor(levels: 3), RadarTileKey(z: 7, x: 32, y: 47))
        XCTAssertEqual(chicago.clamped(toMaxZoom: 8), RadarTileKey(z: 8, x: 65, y: 95))
        XCTAssertEqual(chicago.clamped(toMaxZoom: 12), chicago)
        XCTAssertEqual(chicago.ancestor(levels: 0), chicago)
        XCTAssertEqual(chicago.ancestor(levels: 15), RadarTileKey(z: 0, x: 0, y: 0))
        XCTAssertEqual(chicago.description, "10/262/380")

        // The tile's rectangle in map points contains Chicago's map point, and the keys covering a
        // small rectangle around that point are just that tile.
        let tile = RadarTiling.rect(for: chicago)
        let keys = RadarTiling.keys(minX: tile.x + 10, minY: tile.y + 10, maxX: tile.x + 20, maxY: tile.y + 20, zoom: 10)
        XCTAssertEqual(keys, [chicago])
    }
}

final class CacheReuseTests: XCTestCase {
    let now = Fixtures.now
    var directory: URL!
    var suite: String!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("aisky-reuse-\(UUID().uuidString)")
        suite = "aisky-tests-\(UUID().uuidString)"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    func repository(weatherKit: Bool) throws -> WeatherRepository {
        let store = SharedStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)), cachesDirectory: directory)
        return WeatherRepository(cache: SnapshotCache(directory: directory), store: store, weatherKitAvailable: weatherKit)
    }

    func snapshot(_ source: WeatherDataSource, age: TimeInterval) -> WeatherSnapshot {
        var snapshot = SampleData.snapshot(now: now.addingTimeInterval(-age))
        snapshot.source = source
        return snapshot
    }

    func testWidgetsReuseEitherSourceUntilItIsOld() throws {
        let widget = try repository(weatherKit: false)
        let settings = AppSettings(units: .metric)
        XCTAssertTrue(widget.canReuse(snapshot(.openMeteo, age: 60), settings: settings, maxAge: 600, now: now))
        XCTAssertTrue(widget.canReuse(snapshot(.appleWeather, age: 60), settings: settings, maxAge: 600, now: now))
        XCTAssertFalse(widget.canReuse(snapshot(.appleWeather, age: 601), settings: settings, maxAge: 600, now: now))

        // Choosing Open-Meteo in Settings retires the app's Apple Weather snapshots.
        let openMeteo = AppSettings(units: .metric, dataSource: .openMeteo)
        XCTAssertFalse(widget.canReuse(snapshot(.appleWeather, age: 60), settings: openMeteo, maxAge: 600, now: now))
        XCTAssertTrue(widget.canReuse(snapshot(.openMeteo, age: 60), settings: openMeteo, maxAge: 600, now: now))
    }

    #if canImport(WeatherKit)
    func testAppRefetchesWidgetSnapshotsWhenAppleWeatherIsOn() throws {
        let app = try repository(weatherKit: true)
        let settings = AppSettings(units: .metric)
        XCTAssertFalse(app.canReuse(snapshot(.openMeteo, age: 60), settings: settings, maxAge: 600, now: now))
        XCTAssertTrue(app.canReuse(snapshot(.appleWeather, age: 60), settings: settings, maxAge: 600, now: now))
        XCTAssertTrue(app.canReuse(snapshot(.openMeteo, age: 60), settings: AppSettings(units: .metric, dataSource: .openMeteo), maxAge: 600, now: now))

        // While Apple Weather is failing, Open-Meteo is what the app would fetch anyway.
        app.store.set(WeatherRepository.WeatherKitFailure(date: now, message: "test"), forKey: .weatherKitFailure)
        XCTAssertTrue(app.canReuse(snapshot(.openMeteo, age: 60), settings: settings, maxAge: 600, now: now))
    }
    #endif

    func testReusableCacheEntryIsServedWithoutFetching() async throws {
        let widget = try repository(weatherKit: false)
        let stored = snapshot(.openMeteo, age: 120)
        await widget.cache.store(stored)
        let served = try await widget.snapshot(for: stored.location, settings: AppSettings(units: .metric), maxAge: 600, now: now)
        XCTAssertEqual(served, stored)
    }
}
