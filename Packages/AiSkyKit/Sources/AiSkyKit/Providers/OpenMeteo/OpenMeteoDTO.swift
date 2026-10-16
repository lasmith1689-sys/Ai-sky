import Foundation

// Raw Open-Meteo responses (requested with `timeformat=unixtime`). Every value can be `null`.

struct OMForecastResponse: Decodable {
    let latitude: Double
    let longitude: Double
    let timezone: String?
    let utcOffsetSeconds: Int?
    let current: OMCurrent?
    let minutely15: OMMinutely15?
    let hourly: OMHourly?
    let daily: OMDaily?

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, timezone
        case utcOffsetSeconds = "utc_offset_seconds"
        case current
        case minutely15 = "minutely_15"
        case hourly, daily
    }
}

struct OMCurrent: Decodable {
    let time: TimeInterval
    let temperature: Double?
    let relativeHumidity: Double?
    let dewPoint: Double?
    let apparentTemperature: Double?
    let isDay: Double?
    let precipitation: Double?
    let snowfall: Double?
    let weatherCode: Double?
    let cloudCover: Double?
    let pressure: Double?
    let windSpeed: Double?
    let windDirection: Double?
    let windGusts: Double?
    let visibility: Double?
    let uvIndex: Double?

    enum CodingKeys: String, CodingKey {
        case time
        case temperature = "temperature_2m"
        case relativeHumidity = "relative_humidity_2m"
        case dewPoint = "dew_point_2m"
        case apparentTemperature = "apparent_temperature"
        case isDay = "is_day"
        case precipitation
        case snowfall
        case weatherCode = "weather_code"
        case cloudCover = "cloud_cover"
        case pressure = "pressure_msl"
        case windSpeed = "wind_speed_10m"
        case windDirection = "wind_direction_10m"
        case windGusts = "wind_gusts_10m"
        case visibility
        case uvIndex = "uv_index"
    }
}

struct OMMinutely15: Decodable {
    let time: [TimeInterval]
    let precipitation: [Double?]?
    let snowfall: [Double?]?
    let weatherCode: [Double?]?

    enum CodingKeys: String, CodingKey {
        case time, precipitation, snowfall
        case weatherCode = "weather_code"
    }
}

struct OMHourly: Decodable {
    let time: [TimeInterval]
    let temperature: [Double?]?
    let apparentTemperature: [Double?]?
    let relativeHumidity: [Double?]?
    let dewPoint: [Double?]?
    let precipitationProbability: [Double?]?
    let precipitation: [Double?]?
    let snowfall: [Double?]?
    let weatherCode: [Double?]?
    let cloudCover: [Double?]?
    let pressure: [Double?]?
    let visibility: [Double?]?
    let windSpeed: [Double?]?
    let windDirection: [Double?]?
    let windGusts: [Double?]?
    let uvIndex: [Double?]?
    let isDay: [Double?]?

    enum CodingKeys: String, CodingKey {
        case time
        case temperature = "temperature_2m"
        case apparentTemperature = "apparent_temperature"
        case relativeHumidity = "relative_humidity_2m"
        case dewPoint = "dew_point_2m"
        case precipitationProbability = "precipitation_probability"
        case precipitation
        case snowfall
        case weatherCode = "weather_code"
        case cloudCover = "cloud_cover"
        case pressure = "pressure_msl"
        case visibility
        case windSpeed = "wind_speed_10m"
        case windDirection = "wind_direction_10m"
        case windGusts = "wind_gusts_10m"
        case uvIndex = "uv_index"
        case isDay = "is_day"
    }
}

struct OMDaily: Decodable {
    let time: [TimeInterval]
    let weatherCode: [Double?]?
    let temperatureMax: [Double?]?
    let temperatureMin: [Double?]?
    let apparentTemperatureMax: [Double?]?
    let apparentTemperatureMin: [Double?]?
    let sunrise: [Double?]?
    let sunset: [Double?]?
    let uvIndexMax: [Double?]?
    let precipitationSum: [Double?]?
    let snowfallSum: [Double?]?
    let precipitationHours: [Double?]?
    let precipitationProbabilityMax: [Double?]?
    let windSpeedMax: [Double?]?
    let windGustsMax: [Double?]?
    let windDirectionDominant: [Double?]?

    enum CodingKeys: String, CodingKey {
        case time
        case weatherCode = "weather_code"
        case temperatureMax = "temperature_2m_max"
        case temperatureMin = "temperature_2m_min"
        case apparentTemperatureMax = "apparent_temperature_max"
        case apparentTemperatureMin = "apparent_temperature_min"
        case sunrise, sunset
        case uvIndexMax = "uv_index_max"
        case precipitationSum = "precipitation_sum"
        case snowfallSum = "snowfall_sum"
        case precipitationHours = "precipitation_hours"
        case precipitationProbabilityMax = "precipitation_probability_max"
        case windSpeedMax = "wind_speed_10m_max"
        case windGustsMax = "wind_gusts_10m_max"
        case windDirectionDominant = "wind_direction_10m_dominant"
    }
}

// MARK: Air quality

struct OMAirQualityResponse: Decodable {
    let timezone: String?
    let current: OMAirQualityCurrent?
    let hourly: OMAirQualityHourly?
}

struct OMAirQualityCurrent: Decodable {
    let time: TimeInterval
    let usAQI: Double?
    let europeanAQI: Double?
    let pm10: Double?
    let pm2_5: Double?
    let carbonMonoxide: Double?
    let nitrogenDioxide: Double?
    let sulphurDioxide: Double?
    let ozone: Double?
    let dust: Double?
    let usAQIPM2_5: Double?
    let usAQIPM10: Double?
    let usAQINitrogenDioxide: Double?
    let usAQIOzone: Double?
    let usAQISulphurDioxide: Double?
    let usAQICarbonMonoxide: Double?
    let europeanAQIPM2_5: Double?
    let europeanAQIPM10: Double?
    let europeanAQINitrogenDioxide: Double?
    let europeanAQIOzone: Double?
    let europeanAQISulphurDioxide: Double?
    let alderPollen: Double?
    let birchPollen: Double?
    let grassPollen: Double?
    let mugwortPollen: Double?
    let olivePollen: Double?
    let ragweedPollen: Double?

    enum CodingKeys: String, CodingKey {
        case time
        case usAQI = "us_aqi"
        case europeanAQI = "european_aqi"
        case pm10
        case pm2_5
        case carbonMonoxide = "carbon_monoxide"
        case nitrogenDioxide = "nitrogen_dioxide"
        case sulphurDioxide = "sulphur_dioxide"
        case ozone
        case dust
        case usAQIPM2_5 = "us_aqi_pm2_5"
        case usAQIPM10 = "us_aqi_pm10"
        case usAQINitrogenDioxide = "us_aqi_nitrogen_dioxide"
        case usAQIOzone = "us_aqi_ozone"
        case usAQISulphurDioxide = "us_aqi_sulphur_dioxide"
        case usAQICarbonMonoxide = "us_aqi_carbon_monoxide"
        case europeanAQIPM2_5 = "european_aqi_pm2_5"
        case europeanAQIPM10 = "european_aqi_pm10"
        case europeanAQINitrogenDioxide = "european_aqi_nitrogen_dioxide"
        case europeanAQIOzone = "european_aqi_ozone"
        case europeanAQISulphurDioxide = "european_aqi_sulphur_dioxide"
        case alderPollen = "alder_pollen"
        case birchPollen = "birch_pollen"
        case grassPollen = "grass_pollen"
        case mugwortPollen = "mugwort_pollen"
        case olivePollen = "olive_pollen"
        case ragweedPollen = "ragweed_pollen"
    }
}

struct OMAirQualityHourly: Decodable {
    let time: [TimeInterval]
    let usAQI: [Double?]?
    let europeanAQI: [Double?]?

    enum CodingKeys: String, CodingKey {
        case time
        case usAQI = "us_aqi"
        case europeanAQI = "european_aqi"
    }
}

extension Array {
    /// Returns `nil` instead of trapping when out of range.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Optional where Wrapped == [Double?] {
    /// Value at `index`, flattening both "array missing" and "value is null".
    func value(at index: Int?) -> Double? {
        guard let index, let array = self, let element = array[safe: index] else { return nil }
        return element
    }
}
