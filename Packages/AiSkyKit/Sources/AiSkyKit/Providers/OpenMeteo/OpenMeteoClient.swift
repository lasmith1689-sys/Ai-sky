import Foundation

/// Client for the free Open-Meteo APIs (https://open-meteo.com — CC BY 4.0, non-commercial use).
public struct OpenMeteoClient: Sendable {
    public static let forecastEndpoint = URL(string: "https://api.open-meteo.com/v1/forecast")!
    public static let airQualityEndpoint = URL(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!

    static let currentVariables = [
        "temperature_2m", "relative_humidity_2m", "dew_point_2m", "apparent_temperature", "is_day",
        "precipitation", "snowfall", "weather_code", "cloud_cover", "pressure_msl",
        "wind_speed_10m", "wind_direction_10m", "wind_gusts_10m", "visibility", "uv_index",
    ]
    static let minutelyVariables = ["precipitation", "snowfall", "weather_code"]
    static let hourlyVariables = [
        "temperature_2m", "apparent_temperature", "relative_humidity_2m", "dew_point_2m",
        "precipitation_probability", "precipitation", "snowfall", "weather_code", "cloud_cover",
        "pressure_msl", "visibility", "wind_speed_10m", "wind_direction_10m", "wind_gusts_10m",
        "uv_index", "is_day",
    ]
    static let dailyVariables = [
        "weather_code", "temperature_2m_max", "temperature_2m_min", "apparent_temperature_max",
        "apparent_temperature_min", "sunrise", "sunset", "uv_index_max", "precipitation_sum",
        "snowfall_sum", "precipitation_hours", "precipitation_probability_max", "wind_speed_10m_max",
        "wind_gusts_10m_max", "wind_direction_10m_dominant",
    ]
    static let airQualityCurrentVariables = [
        "us_aqi", "european_aqi", "pm10", "pm2_5", "carbon_monoxide", "nitrogen_dioxide", "sulphur_dioxide",
        "ozone", "dust", "us_aqi_pm2_5", "us_aqi_pm10", "us_aqi_nitrogen_dioxide", "us_aqi_ozone",
        "us_aqi_sulphur_dioxide", "us_aqi_carbon_monoxide", "european_aqi_pm2_5", "european_aqi_pm10",
        "european_aqi_nitrogen_dioxide", "european_aqi_ozone", "european_aqi_sulphur_dioxide",
        "alder_pollen", "birch_pollen", "grass_pollen", "mugwort_pollen", "olive_pollen", "ragweed_pollen",
    ]

    /// Days of forecast shown in the daily list.
    public static let forecastDays = 10
    /// Past days of precipitation history (Precip-style totals).
    public static let historyDays = 31

    let http: HTTPClient

    public init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    // MARK: Requests

    /// Full forecast: current conditions, 15-minute precipitation, a week of hourly history plus
    /// 10 days of hourly forecast, and 31 days of daily precipitation history.
    public func forecast(for location: WeatherLocation, now: Date = Date()) async throws -> WeatherSnapshot {
        let response = try await http.decode(OMForecastResponse.self, from: Self.forecastURL(latitude: location.latitude, longitude: location.longitude))
        return try OpenMeteoMapper.snapshot(from: response, location: location, now: now)
    }

    /// Lightweight current conditions + today's range for many locations in one request.
    public func summaries(for locations: [WeatherLocation], now: Date = Date()) async throws -> [LocationWeatherSummary] {
        guard !locations.isEmpty else { return [] }
        var results: [LocationWeatherSummary] = []
        for chunk in stride(from: 0, to: locations.count, by: 25).map({ Array(locations[$0..<min($0 + 25, locations.count)]) }) {
            let data = try await http.data(from: Self.summaryURL(for: chunk))
            let responses = try Self.decodeOneOrMany(OMForecastResponse.self, from: data)
            for (location, response) in zip(chunk, responses) {
                if let summary = OpenMeteoMapper.summary(from: response, locationID: location.id, now: now) {
                    results.append(summary)
                }
            }
        }
        return results
    }

    /// Only the 15-minute precipitation for the next couple of hours (cheap; used for rain alerts).
    public func nextHour(for location: WeatherLocation, now: Date = Date()) async throws -> NextHourForecast? {
        let response = try await http.decode(OMForecastResponse.self, from: Self.nextHourURL(latitude: location.latitude, longitude: location.longitude))
        return response.minutely15.flatMap { OpenMeteoMapper.minutely(from: $0, now: now) }
    }

    public func airQuality(for location: WeatherLocation) async throws -> AirQuality {
        let response = try await http.decode(OMAirQualityResponse.self, from: Self.airQualityURL(latitude: location.latitude, longitude: location.longitude))
        guard let airQuality = OpenMeteoMapper.airQuality(from: response) else {
            throw WeatherServiceError.noData
        }
        return airQuality
    }

    // MARK: URL building

    static func forecastURL(latitude: Double, longitude: Double) -> URL {
        var components = URLComponents(url: forecastEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: coordinate(latitude)),
            URLQueryItem(name: "longitude", value: coordinate(longitude)),
            URLQueryItem(name: "current", value: currentVariables.joined(separator: ",")),
            URLQueryItem(name: "minutely_15", value: minutelyVariables.joined(separator: ",")),
            URLQueryItem(name: "hourly", value: hourlyVariables.joined(separator: ",")),
            URLQueryItem(name: "daily", value: dailyVariables.joined(separator: ",")),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "past_minutely_15", value: "2"),
            URLQueryItem(name: "forecast_minutely_15", value: "12"),
            URLQueryItem(name: "past_hours", value: "168"),
            URLQueryItem(name: "forecast_hours", value: String(forecastDays * 24)),
            URLQueryItem(name: "past_days", value: String(historyDays)),
            URLQueryItem(name: "forecast_days", value: String(forecastDays)),
        ]
        return components.url!
    }

    static func nextHourURL(latitude: Double, longitude: Double) -> URL {
        var components = URLComponents(url: forecastEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: coordinate(latitude)),
            URLQueryItem(name: "longitude", value: coordinate(longitude)),
            URLQueryItem(name: "minutely_15", value: minutelyVariables.joined(separator: ",")),
            URLQueryItem(name: "past_minutely_15", value: "1"),
            URLQueryItem(name: "forecast_minutely_15", value: "8"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
        ]
        return components.url!
    }

    static func summaryURL(for locations: [WeatherLocation]) -> URL {
        var components = URLComponents(url: forecastEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: locations.map { coordinate($0.latitude) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: locations.map { coordinate($0.longitude) }.joined(separator: ",")),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,cloud_cover,wind_speed_10m"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
        ]
        return components.url!
    }

    static func airQualityURL(latitude: Double, longitude: Double) -> URL {
        var components = URLComponents(url: airQualityEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: coordinate(latitude)),
            URLQueryItem(name: "longitude", value: coordinate(longitude)),
            URLQueryItem(name: "current", value: airQualityCurrentVariables.joined(separator: ",")),
            URLQueryItem(name: "hourly", value: "us_aqi,european_aqi"),
            URLQueryItem(name: "forecast_days", value: "5"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
        ]
        return components.url!
    }

    static func coordinate(_ value: Double) -> String {
        String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// Open-Meteo returns an object for one coordinate and an array for several.
    static func decodeOneOrMany<T: Decodable>(_ type: T.Type, from data: Data) throws -> [T] {
        let decoder = JSONDecoder()
        do {
            if let first = data.first(where: { !($0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09) }), first == UInt8(ascii: "[") {
                return try decoder.decode([T].self, from: data)
            }
            return [try decoder.decode(T.self, from: data)]
        } catch {
            throw WeatherServiceError.decoding(String(describing: error))
        }
    }
}
