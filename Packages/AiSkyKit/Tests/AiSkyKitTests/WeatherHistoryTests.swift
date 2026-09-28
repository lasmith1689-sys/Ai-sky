import Foundation
import XCTest
@testable import AiSkyKit

final class WeatherHistoryClientTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Fixtures.chicago
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func testRecentRangesUseTheForecastAPIOnly() {
        let today = calendar.startOfDay(for: Fixtures.now)
        let segments = WeatherHistoryClient.segments(from: today.addingTimeInterval(-10 * 86400), to: today, today: Fixtures.now, calendar: calendar)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.endpoint, .forecast)
    }

    func testLongRangesAreSplitBetweenArchiveAndForecast() throws {
        let today = calendar.startOfDay(for: Fixtures.now)
        let segments = WeatherHistoryClient.segments(from: day(2024, 1, 1), to: today, today: Fixtures.now, calendar: calendar)
        XCTAssertEqual(segments.map(\.endpoint), [.archive, .forecast])
        let archive = try XCTUnwrap(segments.first)
        let forecast = try XCTUnwrap(segments.last)
        XCTAssertEqual(archive.start, day(2024, 1, 1))
        XCTAssertEqual(calendar.date(byAdding: .day, value: 1, to: archive.end), forecast.start, "no gap and no overlap")
        XCTAssertEqual(calendar.dateComponents([.day], from: forecast.start, to: today).day, WeatherHistoryClient.recentDays)
        XCTAssertEqual(forecast.end, today)
    }

    func testRangesAreClampedToAvailableData() {
        let segments = WeatherHistoryClient.segments(from: day(1901, 5, 1), to: day(1940, 1, 10), today: Fixtures.now, calendar: calendar)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.start, day(1940, 1, 1))
        XCTAssertTrue(WeatherHistoryClient.segments(from: day(2030, 1, 1), to: day(2030, 2, 1), today: Fixtures.now, calendar: calendar).isEmpty)
    }

    func testOldDaysComeFromTheArchiveWithoutForecastOnlyVariables() {
        let url = WeatherHistoryClient.dayURL(latitude: 41.8781, longitude: -87.6298, date: day(2024, 7, 4), calendar: calendar, today: Fixtures.now)
        XCTAssertEqual(url.host, "archive-api.open-meteo.com")
        let items = query(url)
        XCTAssertEqual(items["start_date"], "2024-07-04")
        XCTAssertEqual(items["end_date"], "2024-07-05", "the next day supplies the last hour's precipitation")
        XCTAssertFalse(items["hourly"]?.contains("uv_index") ?? true)
        XCTAssertFalse(items["daily"]?.contains("precipitation_probability_max") ?? true)
        XCTAssertTrue(items["daily"]?.contains("precipitation_sum") ?? false)
    }

    func testRecentAndFutureDaysComeFromTheForecastAPI() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Fixtures.now))!
        let recent = WeatherHistoryClient.dayURL(latitude: 41.8781, longitude: -87.6298, date: yesterday, calendar: calendar, today: Fixtures.now)
        XCTAssertEqual(recent.host, "api.open-meteo.com")
        XCTAssertTrue(query(recent)["hourly"]?.contains("precipitation_probability") ?? false)

        let lastForecastDay = WeatherHistoryClient.latestDate(today: Fixtures.now, calendar: calendar)
        let future = WeatherHistoryClient.dayURL(latitude: 41.8781, longitude: -87.6298, date: lastForecastDay, calendar: calendar, today: Fixtures.now)
        XCTAssertEqual(query(future)["start_date"], query(future)["end_date"], "never asks beyond the forecast range")
    }

    func testNormalsRequestCoversTheClimatePeriod() {
        let items = query(WeatherHistoryClient.normalsURL(latitude: 41.8781, longitude: -87.6298))
        XCTAssertEqual(items["start_date"], "1991-01-01")
        XCTAssertEqual(items["end_date"], "2020-12-31")
        XCTAssertEqual(items["daily"], "precipitation_sum")
    }

    func testArchiveDayIsMappedToTheRequestedLocalDay() throws {
        let response = try JSONDecoder().decode(OMForecastResponse.self, from: Fixtures.data("openmeteo-archive-day"))
        let july4 = day(2024, 7, 4)
        let result = try WeatherHistoryClient.historicalDay(from: response, date: july4, calendar: calendar, today: Fixtures.now)
        XCTAssertEqual(result.date, july4)
        XCTAssertEqual(result.timeZoneIdentifier, "America/Chicago")
        XCTAssertEqual(result.source, .reanalysis)
        XCTAssertFalse(result.isForecast)
        XCTAssertEqual(result.hours.count, 24)
        XCTAssertEqual(result.hours.first?.date, july4)

        // Precipitation reported at 16:00 describes 15:00–16:00.
        let threePM = try XCTUnwrap(result.hours.first { $0.date == july4.addingTimeInterval(15 * 3600) })
        XCTAssertEqual(threePM.precipitationAmount ?? 0, 4.2, accuracy: 0.001)
        // The last hour takes its value from the next day's midnight stamp.
        XCTAssertEqual(result.hours.last?.precipitationAmount ?? 0, 0.1, accuracy: 0.001)

        let summary = try XCTUnwrap(result.summary)
        XCTAssertEqual(summary.high, 31.0, accuracy: 0.001)
        XCTAssertEqual(summary.low, 16.0, accuracy: 0.001)
        XCTAssertEqual(summary.condition, .thunderstorms)
        XCTAssertEqual(result.precipitationTotal ?? 0, 16.9, accuracy: 0.001)
        XCTAssertNil(summary.uvIndexMax)
    }

    func testDailySamplesSkipMissingDaysAndMergeWithoutDuplicates() {
        let json = """
        {"latitude":41.86,"longitude":-87.65,"timezone":"America/Chicago",
         "daily":{"time":[1720069200,1720155600,1720242000],"precipitation_sum":[16.9,null,0.0],"snowfall_sum":[0.0,null,0.0]}}
        """
        let response = try? JSONDecoder().decode(OMForecastResponse.self, from: Data(json.utf8))
        let samples = WeatherHistoryClient.dailySamples(from: response?.daily)
        XCTAssertEqual(samples.map(\.amount), [16.9, 0.0])

        let merged = WeatherHistoryClient.merged(samples + [PrecipitationSample(date: samples[0].date, amount: 17.0)])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first?.amount, 17.0)
    }

    func testDayStringUsesTheLocationsCalendarDay() {
        // 03:30 UTC on July 5 is still July 4 in Chicago.
        let lateEvening = Date(timeIntervalSince1970: 1_720_150_200)
        XCTAssertEqual(WeatherHistoryClient.dayString(lateEvening, calendar: calendar), "2024-07-04")
    }
}

final class PrecipitationNormalsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Five years where it rains 2 mm every day, plus 30 mm on every July 4.
    private func samples() -> [PrecipitationSample] {
        var result: [PrecipitationSample] = []
        var date = calendar.date(from: DateComponents(year: 2016, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2020, month: 12, day: 31))!
        while date <= end {
            let parts = calendar.dateComponents([.month, .day], from: date)
            let amount = parts.month == 7 && parts.day == 4 ? 32.0 : 2.0
            result.append(PrecipitationSample(date: date, amount: amount))
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        return result
    }

    func testLeapYearIndexing() {
        XCTAssertEqual(PrecipitationNormals.index(month: 1, day: 1), 0)
        XCTAssertEqual(PrecipitationNormals.index(month: 2, day: 29), 59)
        XCTAssertEqual(PrecipitationNormals.index(month: 3, day: 1), 60)
        XCTAssertEqual(PrecipitationNormals.index(month: 12, day: 31), 365)
        XCTAssertNil(PrecipitationNormals.index(month: 2, day: 30))
        XCTAssertNil(PrecipitationNormals.index(month: 13, day: 1))
    }

    func testNormalsAverageYearsAndSmoothSpikes() throws {
        let normals = try XCTUnwrap(PrecipitationNormals.compute(from: samples(), calendar: calendar))
        XCTAssertEqual(normals.firstYear, 2016)
        XCTAssertEqual(normals.lastYear, 2020)
        XCTAssertEqual(normals.dailyMeans.count, 366)
        // A one-day spike is spread over the surrounding two weeks…
        let july4 = calendar.date(from: DateComponents(year: 2025, month: 7, day: 4))!
        XCTAssertEqual(normals.mean(on: july4, calendar: calendar), 2 + 30.0 / 15, accuracy: 0.001)
        // …but the total over a longer window is preserved.
        let start = calendar.date(from: DateComponents(year: 2025, month: 6, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2025, month: 7, day: 31))!
        XCTAssertEqual(normals.total(from: start, to: end, calendar: calendar), 61 * 2 + 30, accuracy: 0.001)
        XCTAssertEqual(normals.annualTotal, 365 * 2 + 30, accuracy: 0.001)
    }

    func testNormalsNeedSeveralYears() {
        let oneYear = samples().filter { calendar.component(.year, from: $0.date) == 2020 }
        XCTAssertNil(PrecipitationNormals.compute(from: oneYear, calendar: calendar))
    }

    func testNormalsRoundTripThroughJSON() throws {
        let normals = try XCTUnwrap(PrecipitationNormals.compute(from: samples(), calendar: calendar))
        let decoded = try JSONDecoder().decode(PrecipitationNormals.self, from: JSONEncoder().encode(normals))
        XCTAssertEqual(decoded, normals)
    }
}

final class RainfallRecordTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Fixtures.chicago
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Two years of data: 1 mm every third day, and a 25 mm storm on 2026-09-10.
    private func record(normals: PrecipitationNormals? = nil) -> RainfallRecord {
        var samples: [PrecipitationSample] = []
        var date = day(2024, 9, 1)
        var index = 0
        while date <= day(2026, 9, 28) {
            var amount = index % 3 == 0 ? 1.0 : 0.0
            if date == day(2026, 9, 10) { amount = 25 }
            samples.append(PrecipitationSample(date: date, amount: amount, snowfall: nil))
            date = calendar.date(byAdding: .day, value: 1, to: date)!
            index += 1
        }
        return RainfallRecord(samples: samples, normals: normals, calendar: calendar)
    }

    func testPresetRangesEndToday() {
        let today = day(2026, 9, 28)
        func range(_ period: RainfallPeriod) -> ClosedRange<Date> {
            period.dateRange(today: Fixtures.now, calendar: calendar)
        }
        XCTAssertEqual(range(.last7Days), day(2026, 9, 22)...today)
        XCTAssertEqual(range(.last30Days), day(2026, 8, 30)...today)
        XCTAssertEqual(range(.monthToDate), day(2026, 9, 1)...today)
        XCTAssertEqual(range(.yearToDate), day(2026, 1, 1)...today)
        XCTAssertEqual(range(.last12Months), day(2025, 9, 29)...today)
        XCTAssertEqual(range(.custom(start: day(2026, 10, 5), end: day(2026, 9, 1))), day(2026, 9, 1)...today,
                       "custom ranges are ordered and stop today")
    }

    func testSummaryStatistics() throws {
        let summary = record().summary(for: day(2026, 9, 1)...day(2026, 9, 30))
        XCTAssertEqual(summary.dayCount, 30)
        XCTAssertEqual(summary.missingDays, 2, "Sep 29 and 30 haven't happened")
        let wettest = try XCTUnwrap(summary.wettestDay)
        XCTAssertEqual(wettest.date, day(2026, 9, 10))
        XCTAssertEqual(wettest.amount, 25)
        XCTAssertEqual(summary.longestDrySpell, 2)
        XCTAssertNotNil(summary.lastYear, "September 2025 is fully known")
        XCTAssertNil(summary.normal)
    }

    func testLastYearNeedsCompleteData() {
        let summary = record().summary(for: day(2024, 9, 5)...day(2024, 9, 20))
        XCTAssertNil(summary.lastYear, "2023 isn't in the record")
    }

    func testNormalsAreComparedForTheSameDays() throws {
        let normals = PrecipitationNormals(dailyMeans: Array(repeating: 1.0, count: 366), firstYear: 1991, lastYear: 2020)
        let summary = record(normals: normals).summary(for: day(2026, 9, 1)...day(2026, 9, 28))
        XCTAssertEqual(summary.normal ?? 0, 28, accuracy: 0.001)
        XCTAssertEqual(summary.departureFromNormal ?? 0, summary.total - 28, accuracy: 0.001)
        XCTAssertEqual(summary.fractionOfNormal ?? 0, summary.total / 28, accuracy: 0.001)
    }

    func testBarsGroupByGranularity() {
        let record = record()
        let (daily, dayBars) = record.bars(for: day(2026, 9, 1)...day(2026, 9, 28))
        XCTAssertEqual(daily, .day)
        XCTAssertEqual(dayBars.count, 28)

        let (monthly, monthBars) = record.bars(for: day(2025, 9, 29)...day(2026, 9, 28))
        XCTAssertEqual(monthly, .month)
        XCTAssertEqual(monthBars.count, 13, "partial Sep 2025, 11 full months, partial Sep 2026")
        XCTAssertEqual(monthBars.first?.start, day(2025, 9, 29))
        XCTAssertEqual(monthBars.last?.start, day(2026, 9, 1))
        XCTAssertEqual(monthBars.reduce(0) { $0 + $1.amount }, record.summary(for: day(2025, 9, 29)...day(2026, 9, 28)).total, accuracy: 0.001)
    }

    func testCumulativeEndsAtTheTotal() {
        let record = record()
        let range = day(2026, 1, 1)...day(2026, 9, 28)
        let points = record.cumulative(for: range)
        XCTAssertEqual(points.count, record.eachDay(in: range).count)
        XCTAssertEqual(points.last?.total ?? 0, record.summary(for: range).total, accuracy: 0.001)
        XCTAssertNil(points.last?.normal)
    }

    func testSamplesStampedOffMidnightStillLandOnTheirDay() {
        // An hour before local midnight, e.g. a source that ignored daylight saving time.
        let record = RainfallRecord(samples: [PrecipitationSample(date: day(2026, 7, 4).addingTimeInterval(-3600), amount: 5)], calendar: calendar)
        XCTAssertEqual(record.days[day(2026, 7, 4)]?.amount, 5)
    }

    func testGranularityThresholds() {
        XCTAssertEqual(RainfallGranularity.automatic(forDays: 31), .day)
        XCTAssertEqual(RainfallGranularity.automatic(forDays: 92), .week)
        XCTAssertEqual(RainfallGranularity.automatic(forDays: 366), .month)
        XCTAssertEqual(RainfallGranularity.automatic(forDays: 3650), .year)
    }
}
