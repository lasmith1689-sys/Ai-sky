import Foundation
import XCTest
@testable import AiSkyKit

enum Fixtures {
    /// 2026-09-28 17:20 UTC (12:20 CDT) — the moment the fixtures were "fetched".
    static let now = Date(timeIntervalSince1970: 1_790_616_000)
    static let chicago = TimeZone(identifier: "America/Chicago")!

    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw XCTSkip("Missing fixture \(name)")
        }
        return try Data(contentsOf: url)
    }

    static func forecastResponse() throws -> OMForecastResponse {
        try JSONDecoder().decode(OMForecastResponse.self, from: data("openmeteo-forecast"))
    }

    static func snapshot() throws -> WeatherSnapshot {
        try OpenMeteoMapper.snapshot(from: forecastResponse(), location: location, now: now)
    }

    static let location = WeatherLocation(
        id: "test", name: "Chicago", subtitle: "Illinois", latitude: 41.8781, longitude: -87.6298, countryCode: "US"
    )

    static let imperial = WeatherFormatter(units: .imperial, locale: Locale(identifier: "en_US"))
    static let metric = WeatherFormatter(units: .metric, locale: Locale(identifier: "en_GB"))
}

func minuteForecast(
    start: Date,
    resolution: TimeInterval = 60,
    count: Int = 61,
    chance: Double? = nil,
    kind: PrecipitationKind = .rain,
    intensity: (Int) -> Double
) -> NextHourForecast {
    let samples = (0..<count).map { index -> MinutePrecipitation in
        let value = intensity(index)
        return MinutePrecipitation(
            date: start.addingTimeInterval(Double(index) * resolution),
            intensity: value,
            chance: chance,
            kind: value > 0 ? kind : .none
        )
    }
    return NextHourForecast(minutes: samples, resolution: resolution)
}

extension String {
    /// ICU formats times with a narrow no-break space ("8\u{202F}PM"); compare with plain spaces.
    var normalizedSpaces: String {
        replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}
