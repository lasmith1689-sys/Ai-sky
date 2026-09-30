import Foundation
import XCTest
@testable import AiSkyKit

final class OpenMeteoTests: XCTestCase {
    func testCurrentConditionsAreMappedToMetricModel() throws {
        let snapshot = try Fixtures.snapshot()
        XCTAssertEqual(snapshot.source, .openMeteo)
        XCTAssertEqual(snapshot.timeZoneIdentifier, "America/Chicago")
        XCTAssertEqual(snapshot.location.timeZoneIdentifier, "America/Chicago")

        let current = snapshot.current
        XCTAssertEqual(current.temperature, 21.3, accuracy: 0.001)
        XCTAssertEqual(current.apparentTemperature, 22.9, accuracy: 0.001)
        XCTAssertEqual(current.humidity ?? 0, 0.68, accuracy: 0.001)
        XCTAssertEqual(current.visibility ?? 0, 24.14, accuracy: 0.001, "visibility is converted from meters to km")
        XCTAssertEqual(current.cloudCover ?? 0, 0.55, accuracy: 0.001)
        XCTAssertEqual(current.condition, .partlyCloudy)
        XCTAssertTrue(current.isDaylight)
        XCTAssertEqual(current.pressureTrend, .falling, "pressure drops 0.5 hPa/h in the fixture")
    }

    func testHourlyPrecipitationDescribesTheHourThatStartsAtDate() throws {
        let snapshot = try Fixtures.snapshot()
        // The fixture reports 1.6 mm at 20:00Z and 21:00Z (sums of the preceding hour),
        // i.e. rain during the hours starting 19:00Z and 20:00Z.
        let hourStart = Date(timeIntervalSince1970: 1_790_614_800) // 17:00Z
        let rainy = snapshot.hourly.filter { ($0.precipitationAmount ?? 0) > 1 }.map { $0.date.timeIntervalSince(hourStart) / 3600 }
        XCTAssertTrue(rainy.contains(2))
        XCTAssertTrue(rainy.contains(3))
        let firstRainyHour = try XCTUnwrap(snapshot.hourly.first { $0.date == hourStart.addingTimeInterval(2 * 3600) })
        XCTAssertEqual(firstRainyHour.precipitationChance ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(firstRainyHour.precipitationKind, .rain)
        XCTAssertEqual(firstRainyHour.condition, .rain)
    }

    func testHourlyKeepsOnlyTheLastDayOfHistory() throws {
        let snapshot = try Fixtures.snapshot()
        XCTAssertTrue(snapshot.hourly.allSatisfy { $0.date >= Fixtures.now.addingTimeInterval(-25 * 3600) })
        XCTAssertEqual(snapshot.upcomingHours(from: Fixtures.now, limit: 5).first?.date, Date(timeIntervalSince1970: 1_790_614_800))
    }

    func testNullValuesDoNotDropHours() throws {
        let snapshot = try Fixtures.snapshot()
        let last = try XCTUnwrap(snapshot.hourly.last)
        XCTAssertNil(last.uvIndex)
        XCTAssertNotNil(last.temperature)
    }

    func testDailySplitsHistoryFromForecast() throws {
        let snapshot = try Fixtures.snapshot()
        XCTAssertEqual(snapshot.daily.count, 4, "today plus three days")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Fixtures.chicago
        XCTAssertTrue(calendar.isDate(snapshot.daily[0].date, inSameDayAs: Fixtures.now))
        XCTAssertEqual(snapshot.daily[0].high, 24.1, accuracy: 0.001)
        XCTAssertEqual(snapshot.daily[0].precipitationChance ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(snapshot.daily[2].condition, .thunderstorms)
        XCTAssertNil(snapshot.daily[3].uvIndexMax)

        let history = try XCTUnwrap(snapshot.precipitationHistory)
        XCTAssertEqual(history.daily.map(\.amount), [5.2, 0.0, 0.4])
        XCTAssertFalse(history.hourly.isEmpty)
        XCTAssertTrue(history.hourly.allSatisfy { $0.date.addingTimeInterval(3600) <= Fixtures.now })
    }

    func testMinutelyValuesAreShiftedAndConvertedToRates() throws {
        let snapshot = try Fixtures.snapshot()
        let nextHour = try XCTUnwrap(snapshot.nextHour)
        XCTAssertEqual(nextHour.resolution, 900)
        let wet = nextHour.minutes.filter { $0.intensity > 0 }
        XCTAssertEqual(wet.count, 2)
        // 0.3 mm per 15 minutes = 1.2 mm/h, starting 30 minutes after 17:15Z.
        XCTAssertEqual(wet[0].intensity, 1.2, accuracy: 0.0001)
        XCTAssertEqual(wet[0].date, Date(timeIntervalSince1970: 1_790_615_700 + 1800))
    }

    func testSummaryDecodingAcceptsArrays() throws {
        let data = try Fixtures.data("openmeteo-summaries")
        let responses = try OpenMeteoClient.decodeOneOrMany(OMForecastResponse.self, from: data)
        XCTAssertEqual(responses.count, 2)
        let london = try XCTUnwrap(OpenMeteoMapper.summary(from: responses[1], locationID: "london", now: Fixtures.now))
        XCTAssertEqual(london.condition, .lightRain)
        XCTAssertFalse(london.isDaylight)
        XCTAssertNil(london.precipitationChance)
        XCTAssertEqual(london.timeZoneIdentifier, "Europe/London")
    }

    func testSummaryDecodingAcceptsSingleObject() throws {
        let data = try Fixtures.data("openmeteo-forecast")
        let responses = try OpenMeteoClient.decodeOneOrMany(OMForecastResponse.self, from: data)
        XCTAssertEqual(responses.count, 1)
    }

    func testAirQualityMapping() throws {
        let response = try JSONDecoder().decode(OMAirQualityResponse.self, from: Fixtures.data("openmeteo-airquality"))
        let airQuality = try XCTUnwrap(OpenMeteoMapper.airQuality(from: response))
        XCTAssertEqual(airQuality.usAQI, 57)
        XCTAssertEqual(airQuality.level(for: .us)?.name, "Moderate")
        XCTAssertEqual(airQuality.level(for: .european)?.name, "Fair")
        XCTAssertEqual(airQuality.primaryPollutant(for: .us), .pm2_5)
        XCTAssertEqual(airQuality.pollutants.count, 6)
        XCTAssertTrue(airQuality.pollen.isEmpty, "null pollen values outside Europe are dropped")
        XCTAssertEqual(airQuality.hourly.count, 72)
        let maxima = airQuality.dailyMaxima(for: .us, timeZone: Fixtures.chicago, from: Fixtures.now)
        XCTAssertFalse(maxima.isEmpty)
    }

    func testForecastURLContainsExpectedParameters() throws {
        let url = OpenMeteoClient.forecastURL(latitude: 41.87811, longitude: -87.62979)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        XCTAssertEqual(value("latitude"), "41.8781")
        XCTAssertEqual(value("longitude"), "-87.6298")
        XCTAssertEqual(value("timeformat"), "unixtime")
        XCTAssertEqual(value("timezone"), "auto")
        XCTAssertEqual(value("past_days"), "31")
        XCTAssertTrue(value("hourly")?.contains("precipitation_probability") ?? false)
        XCTAssertTrue(value("current")?.contains("apparent_temperature") ?? false)
    }
}
