import Foundation
import XCTest
@testable import AiSkyKit

final class LookSettingTests: XCTestCase {
    func testDefaultIsInstrument() {
        XCTAssertEqual(Look.default, .instrument)
        XCTAssertEqual(AppSettings(units: .imperial).look, .instrument)
        XCTAssertEqual(AppSettings.defaults(for: Locale(identifier: "en_US")).look, .instrument)
    }

    func testSettingsSavedBeforeLooksExistedGetInstrument() throws {
        // What an existing install has on disk: every key but `look`.
        let old = AppSettings(units: .imperial, dataSource: .openMeteo, rainAlertsEnabled: true)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "look")
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.look, .instrument)
        XCTAssertEqual(decoded.dataSource, .openMeteo)
        XCTAssertTrue(decoded.rainAlertsEnabled)
    }

    func testUnknownLookFallsBackToInstrument() throws {
        let json = #"{"look": "vaporwave", "rainAlertsEnabled": true}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.look, .instrument)
        XCTAssertTrue(decoded.rainAlertsEnabled)
        XCTAssertEqual(try JSONDecoder().decode(Look.self, from: Data(#""sepia""#.utf8)), .instrument)
        XCTAssertEqual(Look(id: nil), .instrument)
        XCTAssertEqual(Look(id: "chroma"), .chroma)
    }

    func testLookPersistsThroughTheSharedStore() throws {
        let suite = "LookSettingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SharedStore(defaults: defaults, cachesDirectory: FileManager.default.temporaryDirectory)
        XCTAssertEqual(store.loadSettings().look, .instrument)
        for look in Look.allCases {
            var settings = store.loadSettings()
            settings.look = look
            store.saveSettings(settings)
            XCTAssertEqual(store.loadSettings().look, look)
        }
    }

    func testEveryLookHasANameAndSummaryWithoutEmDashes() {
        XCTAssertEqual(Look.allCases.map(\.rawValue), ["liquid", "obsidian", "instrument", "editorial", "horizon", "chroma"])
        for look in Look.allCases {
            XCTAssertFalse(look.displayName.isEmpty)
            XCTAssertFalse(look.summary.contains("\u{2014}"))
        }
    }
}

#if canImport(SwiftUI)
final class LookTokensTests: XCTestCase {
    func testTokensMatchTheirLook() {
        for look in Look.allCases {
            XCTAssertEqual(LookTokens.tokens(for: look).look, look)
        }
        XCTAssertTrue(LookTokens.liquid.usesSky)
        XCTAssertEqual(LookTokens.editorial.colorScheme, .light)
        XCTAssertEqual(LookTokens.chroma.colorScheme, .light)
        XCTAssertEqual(LookTokens.obsidian.colorScheme, .dark)
        XCTAssertEqual(LookTokens.instrument.surfaceStyle, .flat)
    }

    func testBundledFontNamesAreUniqueAndCoverTheTokens() {
        XCTAssertEqual(Set(LookFonts.all).count, LookFonts.all.count)
        XCTAssertTrue(Set(LookFonts.widget).isSubset(of: Set(LookFonts.all)))
        for look in Look.allCases {
            let tokens = LookTokens.tokens(for: look)
            let faces = [tokens.display, tokens.headline, tokens.text, tokens.textMedium, tokens.textStrong,
                         tokens.label, tokens.number, tokens.numberLight, tokens.emphasis]
            for face in faces {
                if let name = face.postScriptName {
                    XCTAssertTrue(LookFonts.all.contains(name), "\(look): \(name) isn't bundled")
                } else {
                    XCTAssertEqual(look, .liquid, "only Liquid uses the system font")
                }
            }
        }
    }

    func testTwentyFourHourClock() {
        let date = Fixtures.now.addingTimeInterval(3 * 3600) // 15:20 in Chicago
        XCTAssertEqual(LookClock.time(date, timeZone: Fixtures.chicago, tokens: .instrument, formatter: Fixtures.imperial), "15:20")
        XCTAssertEqual(LookClock.hour(date, timeZone: Fixtures.chicago, tokens: .obsidian, formatter: Fixtures.imperial), "15")
        XCTAssertEqual(LookClock.time(date, timeZone: Fixtures.chicago, tokens: .editorial, formatter: Fixtures.imperial).normalizedSpaces, "3:20 PM")
    }
}
#endif

final class GaugeScaleTests: XCTestCase {
    func testMockupDay() {
        // The design mockup: 54° to 68°, 64° now, on a 40 to 80 dial.
        let scale = GaugeScale.fitting(low: 54, high: 68, current: 64, labelStep: 10)
        XCTAssertEqual(scale.lower, 40)
        XCTAssertEqual(scale.upper, 80)
        XCTAssertEqual(scale.labels, [40, 50, 60, 70, 80])
        XCTAssertEqual(scale.fraction(64), 0.6, accuracy: 1e-9)
        XCTAssertEqual(scale.angle(64), 297, accuracy: 1e-9)
        XCTAssertEqual(scale.angle(54), 229.5, accuracy: 1e-9)
        XCTAssertEqual(scale.angle(68), 324, accuracy: 1e-9)
        let ticks = scale.ticks
        XCTAssertEqual(ticks.count, 41)
        XCTAssertEqual(ticks.filter(\.isMajor).map(\.value), [40, 45, 50, 55, 60, 65, 70, 75, 80])
    }

    func testSteadyDayStaysFourStepsWide() {
        let scale = GaugeScale.fitting(low: 71, high: 73, current: 72, labelStep: 10)
        XCTAssertEqual(scale.span, 40)
        XCTAssertEqual(scale.lower, 50)
        XCTAssertEqual(scale.upper, 90)
    }

    func testCelsiusUsesFiveDegreeLabels() {
        let scale = GaugeScale.fitting(low: 12, high: 20, current: 15, labelStep: 5)
        XCTAssertEqual(scale.lower, 5)
        XCTAssertEqual(scale.upper, 25)
        XCTAssertEqual(scale.labels, [5, 10, 15, 20, 25])
        XCTAssertEqual(scale.minorStep, 0.5, accuracy: 1e-9)
        XCTAssertEqual(scale.ticks.count, 41)
    }

    func testBelowFreezingHasNoNegativeZero() {
        let scale = GaugeScale.fitting(low: -12, high: -3, current: -7, labelStep: 5)
        XCTAssertEqual(scale.lower, -20)
        XCTAssertEqual(scale.upper, 0)
        XCTAssertEqual(scale.labels.last, 0)
        XCTAssertFalse(scale.labels.last!.sign == .minus)
    }

    func testWideRangeLabelsEveryOtherStep() {
        let scale = GaugeScale.fitting(low: 20, high: 95, current: 60, labelStep: 10)
        XCTAssertEqual(scale.labelStep, 20)
        XCTAssertEqual(scale.lower, 0)
        XCTAssertEqual(scale.upper, 120)
        XCTAssertLessThanOrEqual(scale.labels.count, 9)
        XCTAssertLessThanOrEqual(scale.ticks.count, 61)
    }

    func testCurrentOutsideTheDailyRangeIsIncluded() {
        let scale = GaugeScale.fitting(low: 50, high: 60, current: 72, labelStep: 10)
        XCTAssertGreaterThan(scale.fraction(72), 0)
        XCTAssertLessThan(scale.fraction(72), 1)
    }

    func testFractionIsClamped() {
        let scale = GaugeScale(lower: 40, upper: 80, labelStep: 10, majorStep: 5, minorStep: 1)
        XCTAssertEqual(scale.fraction(20), 0)
        XCTAssertEqual(scale.fraction(100), 1)
    }
}

final class NextHourWindowTests: XCTestCase {
    let now = Fixtures.now // 12:20 in Chicago

    private func clock(_ date: Date) -> String {
        LookClock.twentyFourHour(date, timeZone: Fixtures.chicago, pattern: "HH:mm")
    }

    func testStartingAndStopping() {
        let forecast = minuteForecast(start: now) { $0 >= 12 && $0 < 37 ? 0.6 : 0 }
        let window = NextHourWindow(forecast: forecast, now: now)
        XCTAssertEqual(window.state, .starting)
        XCTAssertEqual(window.startsInMinutes, 12)
        XCTAssertEqual(window.endsInMinutes, 37)
        XCTAssertEqual(window.phrase, "light rain")
        XCTAssertEqual(window.instrumentHeader(clock: clock), "RAIN 12:32 → 12:57")
        XCTAssertEqual(window.obsidianHeader(clock: clock), "LIGHT RAIN 12:32 TO 12:57")
        XCTAssertEqual(window.sentence(clock: clock), "Rain in 12 min, gone by 12:57.")
        XCTAssertEqual(window.editorialNote(clock: clock), "Light rain, 12:32 to 12:57")
        XCTAssertEqual(window.chromaTitle(clock: clock), "Rain at 12:32, done by 12:57")
        XCTAssertEqual(window.liquidTitle, "Light rain in 12 min")
        XCTAssertEqual(window.liquidDetail(clock: clock), "until about 12:57")
        XCTAssertEqual(window.status(long: true), "Rain in 12 minutes")
        XCTAssertEqual(window.intensityWord, "Light")
    }

    func testStoppingStartsNow() {
        let forecast = minuteForecast(start: now) { $0 < 20 ? 2.0 : 0 }
        let window = NextHourWindow(forecast: forecast, now: now)
        XCTAssertEqual(window.state, .stopping)
        XCTAssertNil(window.start)
        XCTAssertEqual(window.instrumentHeader(clock: clock), "RAIN NOW → 12:40")
        XCTAssertEqual(window.status(), "Rain ending in 20 min")
        XCTAssertEqual(window.chromaTitle(clock: clock), "Rain now, done by 12:40")
    }

    func testSnowForTheHour() {
        let forecast = minuteForecast(start: now, kind: .snow) { _ in 1.0 }
        let window = NextHourWindow(forecast: forecast, now: now)
        XCTAssertEqual(window.instrumentHeader(clock: clock), "SNOW ALL HOUR")
        XCTAssertEqual(window.sentence(clock: clock), "Snow for the next hour.")
    }

    func testDryAndUnavailable() {
        let dry = NextHourWindow(forecast: minuteForecast(start: now) { _ in 0 }, now: now)
        XCTAssertFalse(dry.isPrecipitating)
        XCTAssertEqual(dry.instrumentHeader(clock: clock), "NO RAIN")
        XCTAssertNil(dry.sentence(clock: clock))
        XCTAssertNil(dry.status())
        let missing = NextHourWindow(forecast: nil, now: now)
        XCTAssertEqual(missing.state, .unavailable)
        XCTAssertEqual(missing.instrumentHeader(clock: clock), "NO MINUTE DATA")
    }

    func testFifteenMinuteDataIsApproximate() {
        let forecast = minuteForecast(start: now, resolution: 900, count: 5) { $0 == 2 ? 1.5 : 0 }
        let window = NextHourWindow(forecast: forecast, now: now)
        XCTAssertTrue(window.isApproximate)
        XCTAssertTrue(window.status()?.contains("about") ?? false)
    }
}

final class EditorialHeadlineTests: XCTestCase {
    func testClockWords() {
        func at(_ hour: Int, _ minute: Int) -> Date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = Fixtures.chicago
            return calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: hour, minute: minute))!
        }
        XCTAssertEqual(ClockWords.phrase(at(16, 10), timeZone: Fixtures.chicago), "ten past four")
        XCTAssertEqual(ClockWords.phrase(at(16, 9), timeZone: Fixtures.chicago), "ten past four")
        XCTAssertEqual(ClockWords.phrase(at(18, 30), timeZone: Fixtures.chicago), "half past six")
        XCTAssertEqual(ClockWords.phrase(at(8, 45), timeZone: Fixtures.chicago), "quarter to nine")
        XCTAssertEqual(ClockWords.phrase(at(21, 40), timeZone: Fixtures.chicago), "twenty to ten")
        XCTAssertEqual(ClockWords.phrase(at(16, 0), timeZone: Fixtures.chicago), "four o'clock")
        XCTAssertEqual(ClockWords.phrase(at(11, 58), timeZone: Fixtures.chicago), "noon")
        XCTAssertEqual(ClockWords.phrase(at(23, 59), timeZone: Fixtures.chicago), "midnight")
        XCTAssertEqual(ClockWords.phrase(at(14, 25), timeZone: Fixtures.chicago), "twenty-five past two")
    }

    func testMockupSentence() {
        // The mockup: rain starting in 18 minutes and stopping at 4:10.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Fixtures.chicago
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 15, minute: 12))!
        let forecast = minuteForecast(start: now) { $0 >= 18 && $0 < 58 ? 0.6 : 0 }
        let window = NextHourWindow(forecast: forecast, now: now)
        let sentence = EditorialHeadline.sentence(window: window, timeZone: Fixtures.chicago, fallback: "Dry.")
        XCTAssertEqual(sentence, "Rain arrives in eighteen minutes and is gone by ten past four.")
    }

    func testDryUsesTheFallback() {
        let window = NextHourWindow(forecast: minuteForecast(start: Fixtures.now) { _ in 0 }, now: Fixtures.now)
        XCTAssertEqual(EditorialHeadline.sentence(window: window, timeZone: Fixtures.chicago, fallback: "Partly cloudy until 6 PM, then clear."),
                       "Partly cloudy until 6 PM, then clear.")
    }

    func testHeavyRainAndNoEnd() {
        let now = Fixtures.now
        let forecast = minuteForecast(start: now) { $0 >= 5 ? 12.0 : 0 }
        let window = NextHourWindow(forecast: forecast, now: now)
        XCTAssertEqual(EditorialHeadline.sentence(window: window, timeZone: Fixtures.chicago, fallback: ""),
                       "Heavy rain arrives in five minutes and lasts the rest of the hour.")
    }
}

final class MinuteBarsTests: XCTestCase {
    func testThirtyTwoMinuteBars() {
        let now = Fixtures.now
        let forecast = minuteForecast(start: now) { $0 >= 20 && $0 < 30 ? 2.0 : 0 }
        let bars = MinuteChartData.bars(for: forecast, now: now, count: 30)
        XCTAssertEqual(bars.count, 30)
        XCTAssertEqual(bars[9], 0)
        XCTAssertGreaterThan(bars[10], MinuteChartData.wetThreshold)
        XCTAssertGreaterThan(bars[14], MinuteChartData.wetThreshold)
        XCTAssertEqual(bars[15], 0)
        XCTAssertLessThan(MinuteChartData.wetThreshold, 0.05)
    }
}
