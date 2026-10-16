import Foundation
import XCTest
@testable import AiSkyKit

final class NextHourSummaryTests: XCTestCase {
    let now = Fixtures.now

    func testDryHour() {
        let forecast = minuteForecast(start: now) { _ in 0 }
        let summary = NextHourSummarizer.summarize(forecast, now: now)
        XCTAssertEqual(summary.state, .dry)
        XCTAssertEqual(summary.text, "No precipitation expected for the next hour.")
        XCTAssertFalse(summary.isPrecipitationExpected)
    }

    func testRainStartingAndStopping() {
        let forecast = minuteForecast(start: now) { $0 >= 12 && $0 < 37 ? 0.6 : 0 }
        let summary = NextHourSummarizer.summarize(forecast, now: now)
        XCTAssertEqual(summary.state, .starting)
        XCTAssertEqual(summary.text, "Light rain starting in 12 min, stopping 25 min later.")
        XCTAssertEqual(summary.shortText, "Rain in 12 min")
        XCTAssertEqual(summary.startsIn ?? 0, 12 * 60, accuracy: 1)
        XCTAssertEqual(summary.endsIn ?? 0, 37 * 60, accuracy: 1)
    }

    func testHeavyRainForTheHour() {
        let forecast = minuteForecast(start: now) { _ in 12 }
        let summary = NextHourSummarizer.summarize(forecast, now: now)
        XCTAssertEqual(summary.state, .continuing)
        XCTAssertEqual(summary.text, "Heavy rain for the hour.")
        XCTAssertEqual(summary.intensity, .heavy)
    }

    func testRainStoppingSoonAndReturning() {
        let forecast = minuteForecast(start: now) { index in
            switch index {
            case ..<10: return 2.0
            case 10..<30: return 0
            default: return 2.0
            }
        }
        let summary = NextHourSummarizer.summarize(forecast, now: now)
        XCTAssertEqual(summary.state, .stopping)
        XCTAssertEqual(summary.text, "Rain stopping in 10 min, starting again 20 min later.")
        XCTAssertEqual(summary.shortText, "Rain ending in 10 min")
    }

    func testBriefBlipsAreIgnored() {
        // A single wet minute is noise; the real rain starts at minute 40.
        let forecast = minuteForecast(start: now) { index in
            if index == 5 { return 0.5 }
            return index >= 40 ? 0.5 : 0
        }
        let summary = NextHourSummarizer.summarize(forecast, now: now)
        XCTAssertEqual(summary.state, .starting)
        XCTAssertEqual(Int((summary.startsIn ?? 0) / 60), 40)
    }

    func testLowProbabilityIsPossible() {
        let forecast = minuteForecast(start: now, chance: 0.35) { $0 >= 20 ? 0.3 : 0 }
        let summary = NextHourSummarizer.summarize(forecast, now: now)
        XCTAssertTrue(summary.isPossibleOnly)
        XCTAssertTrue(summary.text.hasPrefix("Possible light rain starting in 20 min"), summary.text)
    }

    func testVeryLowProbabilityIsIgnored() {
        let forecast = minuteForecast(start: now, chance: 0.1) { _ in 3 }
        XCTAssertEqual(NextHourSummarizer.summarize(forecast, now: now).state, .dry)
    }

    func testSnow() {
        let forecast = minuteForecast(start: now, kind: .snow) { $0 >= 5 ? 0.2 : 0 }
        let summary = NextHourSummarizer.summarize(forecast, now: now)
        XCTAssertEqual(summary.text, "Light snow starting in 5 min.")
        XCTAssertEqual(summary.shortText, "Snow in 5 min")
    }

    func testFifteenMinuteDataIsApproximate() throws {
        let snapshot = try Fixtures.snapshot()
        let summary = NextHourSummarizer.summarize(snapshot.nextHour, now: now)
        XCTAssertEqual(summary.state, .starting)
        XCTAssertEqual(summary.text, "Rain starting in about 25 min, stopping about 30 min later.")
    }

    func testProviderTextIsPreferred() {
        var forecast = minuteForecast(start: now) { $0 >= 12 ? 0.6 : 0 }
        forecast.providerSummary = "Light rain starting in 12 min"
        let summary = NextHourSummarizer.summarize(forecast, now: now)
        XCTAssertEqual(summary.text, "Light rain starting in 12 min.")
        XCTAssertEqual(summary.state, .starting)
    }

    func testUnavailableWithoutData() {
        XCTAssertEqual(NextHourSummarizer.summarize(nil, now: now).state, .unavailable)
        let old = minuteForecast(start: now.addingTimeInterval(-7200)) { _ in 1 }
        XCTAssertEqual(NextHourSummarizer.summarize(old, now: now).state, .unavailable)
    }

    func testChartScaleMatchesDarkSkyGuides() {
        XCTAssertEqual(PrecipitationIntensity.chartValue(millimetersPerHour: 0), 0)
        XCTAssertEqual(PrecipitationIntensity.chartValue(millimetersPerHour: PrecipitationIntensity.lightRate), 1.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(PrecipitationIntensity.chartValue(millimetersPerHour: PrecipitationIntensity.moderateRate), 2.0 / 3, accuracy: 0.0001)
        XCTAssertEqual(PrecipitationIntensity.chartValue(millimetersPerHour: PrecipitationIntensity.heavyRate), 1, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(PrecipitationIntensity.chartValue(millimetersPerHour: 200), 1.1)
        XCTAssertEqual(PrecipitationIntensity(millimetersPerHour: 0.01), PrecipitationIntensity.none)
        XCTAssertEqual(PrecipitationIntensity(millimetersPerHour: 0.5), .light)
        XCTAssertEqual(PrecipitationIntensity(millimetersPerHour: 3), .moderate)
    }
}

final class MinuteChartDataTests: XCTestCase {
    func testMinuteDataProducesOnePointPerMinute() {
        let now = Fixtures.now
        let forecast = minuteForecast(start: now) { $0 >= 30 ? 2.54 : 0 }
        let points = MinuteChartData.points(for: forecast, now: now)
        XCTAssertEqual(points.count, 61)
        XCTAssertEqual(points.first?.minute, 0)
        XCTAssertEqual(points.last?.minute, 60)
        XCTAssertEqual(points[45].value, 2.0 / 3, accuracy: 0.0001)
    }

    func testQuarterHourDataIsInterpolated() throws {
        let snapshot = try Fixtures.snapshot()
        let points = MinuteChartData.points(for: try XCTUnwrap(snapshot.nextHour), now: Fixtures.now)
        XCTAssertEqual(points.count, 61)
        XCTAssertEqual(points[0].value, 0, accuracy: 0.0001)
        // Peak sits in the middle of the wet half hour (17:45–18:15Z = 25–55 min from now).
        let peak = try XCTUnwrap(points.max { $0.value < $1.value })
        XCTAssertTrue((30...50).contains(peak.minute), "peak at \(peak.minute)")
    }
}
