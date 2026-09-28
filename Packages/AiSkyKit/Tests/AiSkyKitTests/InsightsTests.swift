import Foundation
import XCTest
@testable import AiSkyKit

final class InsightsTests: XCTestCase {
    func hours(from start: Date, count: Int = 24, _ make: (Int) -> (SkyCondition, Double?, Double?)) -> [HourlyForecast] {
        (0..<count).map { index in
            let (condition, chance, amount) = make(index)
            return HourlyForecast(
                date: start.addingTimeInterval(Double(index) * 3600),
                condition: condition,
                isDaylight: true,
                temperature: 20,
                precipitationChance: chance,
                precipitationAmount: amount,
                precipitationKind: condition.precipitationKind
            )
        }
    }

    var hourStart: Date { Date(timeIntervalSince1970: 1_790_614_800) } // 12:00 CDT

    func testDaySummaryAllDayRain() {
        let forecast = hours(from: hourStart) { _ in (.rain, 0.9, 1.5) }
        let text = ForecastNarrator.daySummary(hours: forecast, now: Fixtures.now, timeZone: Fixtures.chicago, formatter: Fixtures.imperial)
        XCTAssertEqual(text, "Rain throughout the day.")
    }

    func testDaySummaryRainWindow() {
        let forecast = hours(from: hourStart) { index in
            (3...6).contains(index) ? (.lightRain, 0.7, 0.6) : (.partlyCloudy, 0.1, 0)
        }
        let text = ForecastNarrator.daySummary(hours: forecast, now: Fixtures.now, timeZone: Fixtures.chicago, formatter: Fixtures.imperial)
        XCTAssertEqual(text.normalizedSpaces, "Light rain from 3 PM to 7 PM.")
    }

    func testDaySummaryRainStartingLater() {
        let forecast = hours(from: hourStart) { index in
            index >= 8 ? (.snow, 0.8, 1.2) : (.cloudy, 0.2, 0)
        }
        let text = ForecastNarrator.daySummary(hours: forecast, now: Fixtures.now, timeZone: Fixtures.chicago, formatter: Fixtures.imperial)
        XCTAssertEqual(text.normalizedSpaces, "Snow starting around 8 PM.")
    }

    func testDaySummaryDryChangesSky() {
        let forecast = hours(from: hourStart) { index in
            index < 6 ? (.partlyCloudy, 0.05, 0) : (.clear, 0.0, 0)
        }
        let text = ForecastNarrator.daySummary(hours: forecast, now: Fixtures.now, timeZone: Fixtures.chicago, formatter: Fixtures.imperial)
        XCTAssertEqual(text.normalizedSpaces, "Partly cloudy until 6 PM, then clear.")
    }

    func testDaySummaryMentionsGusts() {
        var forecast = hours(from: hourStart) { _ in (.clear, 0, 0) }
        forecast[4].windGust = 64
        let text = ForecastNarrator.daySummary(hours: forecast, now: Fixtures.now, timeZone: Fixtures.chicago, formatter: Fixtures.imperial)
        XCTAssertEqual(text, "Clear throughout the day. Gusts up to 40 mph.")
    }

    func testWeekSummary() throws {
        let snapshot = SampleData.snapshot(now: Fixtures.now)
        let text = ForecastNarrator.weekSummary(days: snapshot.daily, now: Fixtures.now, timeZone: Fixtures.chicago, formatter: Fixtures.imperial)
        XCTAssertTrue(text.hasPrefix("Rain today"), text)
        XCTAssertTrue(text.contains("with high temperatures"), text)
        XCTAssertTrue(text.hasSuffix("."))
    }

    func testFeelsLike() {
        XCTAssertEqual(FeelsLikeInsight.explanation(temperature: 30, apparentTemperature: 35, humidity: 0.7, windSpeed: 5, isDaylight: true),
                       "Humidity is making it feel warmer.")
        XCTAssertEqual(FeelsLikeInsight.explanation(temperature: 2, apparentTemperature: -4, humidity: 0.6, windSpeed: 30, isDaylight: false),
                       "Wind is making it feel colder.")
        XCTAssertEqual(FeelsLikeInsight.explanation(temperature: 15, apparentTemperature: 15.5, humidity: 0.5, windSpeed: 5, isDaylight: true),
                       "Similar to the actual temperature.")
    }

    func testUVCategories() {
        XCTAssertEqual(UVCategory(index: 2.4), .low)
        XCTAssertEqual(UVCategory(index: 5.4), .moderate)
        XCTAssertEqual(UVCategory(index: 7), .high)
        XCTAssertEqual(UVCategory(index: 10), .veryHigh)
        XCTAssertEqual(UVCategory(index: 11), .extreme)
    }

    func testMoonPhases() {
        // Full moon: 2024-01-25 17:54 UTC. New moon: 2024-01-11 11:57 UTC.
        let full = MoonCalculator.moon(on: Date(timeIntervalSince1970: 1_706_205_240))
        XCTAssertEqual(full.phase, .fullMoon)
        XCTAssertGreaterThan(full.illumination, 0.97)
        let new = MoonCalculator.moon(on: Date(timeIntervalSince1970: 1_704_974_220))
        XCTAssertEqual(new.phase, .newMoon)
        XCTAssertLessThan(new.illumination, 0.03)
        XCTAssertGreaterThan(new.nextFullMoon, Date(timeIntervalSince1970: 1_704_974_220))
    }

    func testAQILevels() {
        XCTAssertEqual(AQIScale.us.level(for: 42).name, "Good")
        XCTAssertEqual(AQIScale.us.level(for: 101).name, "Unhealthy for Sensitive Groups")
        XCTAssertEqual(AQIScale.us.level(for: 350).name, "Hazardous")
        XCTAssertEqual(AQIScale.european.level(for: 45).name, "Moderate")
        XCTAssertEqual(AQIScale.european.level(for: 5).name, "Good")
    }

    func testPollenLevels() {
        XCTAssertEqual(PollenReading(type: .grass, concentration: 25).level, .high)
        XCTAssertEqual(PollenReading(type: .birch, concentration: 10).level, .low)
        XCTAssertEqual(PollenReading(type: .ragweed, concentration: 0).level, PollenLevel.none)
    }

    func testWMOCodeMapping() {
        XCTAssertEqual(SkyCondition(wmoCode: 0, cloudCover: 0.5), .partlyCloudy)
        XCTAssertEqual(SkyCondition(wmoCode: 3, cloudCover: 0.95), .cloudy)
        XCTAssertEqual(SkyCondition(wmoCode: 95), .thunderstorms)
        XCTAssertEqual(SkyCondition(wmoCode: 1, windSpeedKmh: 50), .windy)
        XCTAssertEqual(SkyCondition(wmoCode: 63, windSpeedKmh: 50), .rain, "wind never overrides precipitation")
        XCTAssertEqual(SkyCondition(wmoCode: 75).precipitationKind, .snow)
        XCTAssertEqual(SkyCondition(wmoCode: 66).precipitationKind, .sleet)
    }

    func testPrecipitationTotals() throws {
        let snapshot = try Fixtures.snapshot()
        let totals = PrecipitationTotals.compute(for: snapshot, now: Fixtures.now)
        // History: 0.8 mm at two hours ~10 hours ago.
        XCTAssertEqual(totals.past24Hours ?? 0, 1.6, accuracy: 0.001)
        XCTAssertEqual(totals.pastHour ?? -1, 0, accuracy: 0.001)
        // Forecast: 1.6 mm in each of two hours later today.
        XCTAssertEqual(totals.next24Hours ?? 0, 3.2, accuracy: 0.001)
        // 15-minute data: 0.3 mm in each of the two quarter hours starting at 17:45Z.
        XCTAssertEqual(totals.nextHour ?? -1, 0.6, accuracy: 0.001)
        XCTAssertNotNil(totals.lastPrecipitation)
        XCTAssertEqual(totals.dailyBars.filter(\.isToday).count, 1)
        XCTAssertEqual(totals.dailyBars.count, 3 + 1 + 3)
        XCTAssertTrue(totals.hasAnyPrecipitation)
    }

    func testPrecipitationTotalsFromSampleData() {
        let snapshot = SampleData.snapshot(now: Fixtures.now)
        let totals = PrecipitationTotals.compute(for: snapshot, now: Fixtures.now)
        XCTAssertEqual(totals.past7Days ?? 0, 1.4 * 5 + 4.0, accuracy: 0.001)
        XCTAssertGreaterThan(totals.past30Days ?? 0, 0)
        XCTAssertEqual(totals.dailyBars.count, 14 + 1 + 6)
        XCTAssertGreaterThan(totals.nextHour ?? 0, 0)
    }
}
