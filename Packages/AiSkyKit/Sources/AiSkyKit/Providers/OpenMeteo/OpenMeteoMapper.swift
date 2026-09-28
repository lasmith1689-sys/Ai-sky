import Foundation

/// Converts raw Open-Meteo responses into provider-independent models.
///
/// Open-Meteo reports precipitation, precipitation probability and the weather code as
/// values for the *preceding* hour (or 15 minutes). The app's models describe the period
/// *starting* at `date` (like Apple Weather), so those values are shifted by one step.
enum OpenMeteoMapper {
    static func snapshot(from response: OMForecastResponse, location: WeatherLocation, now: Date) throws -> WeatherSnapshot {
        guard let currentBlock = response.current, let temperature = currentBlock.temperature else {
            throw WeatherServiceError.noData
        }
        let timeZoneID = response.timezone ?? location.timeZoneIdentifier ?? TimeZone.current.identifier
        let timeZone = TimeZone(identifier: timeZoneID) ?? .current

        let allHours = response.hourly.map(hourly(from:)) ?? []
        let current = self.current(from: currentBlock, temperature: temperature, hours: allHours)
        let (days, pastDays) = response.daily.map { daily(from: $0, timeZone: timeZone, now: now) } ?? ([], [])
        let history = precipitationHistory(hourly: response.hourly, pastDays: pastDays, now: now)
        let nextHour = response.minutely15.flatMap { minutely(from: $0, now: now) }

        var resolvedLocation = location
        resolvedLocation.timeZoneIdentifier = timeZoneID

        return WeatherSnapshot(
            location: resolvedLocation,
            fetchedAt: now,
            source: .openMeteo,
            timeZoneIdentifier: timeZoneID,
            current: current,
            nextHour: nextHour,
            hourly: allHours.filter { $0.date >= now.addingTimeInterval(-24 * 3600) },
            daily: days,
            precipitationHistory: history
        )
    }

    // MARK: Current

    static func current(from c: OMCurrent, temperature: Double, hours: [HourlyForecast]) -> CurrentConditions {
        let now = Date(timeIntervalSince1970: c.time)
        let cloudCover = c.cloudCover.map { $0 / 100 }
        let code = c.weatherCode.map { Int($0) } ?? 3
        let condition = SkyCondition(wmoCode: code, cloudCover: cloudCover, windSpeedKmh: c.windSpeed)
        return CurrentConditions(
            date: now,
            condition: condition,
            isDaylight: (c.isDay ?? 1) > 0.5,
            temperature: temperature,
            apparentTemperature: c.apparentTemperature ?? temperature,
            humidity: c.relativeHumidity.map { $0 / 100 },
            dewPoint: c.dewPoint,
            pressure: c.pressure,
            pressureTrend: pressureTrend(hours: hours, now: now, currentPressure: c.pressure),
            windSpeed: c.windSpeed,
            windGust: c.windGusts,
            windDirection: c.windDirection,
            uvIndex: c.uvIndex,
            visibility: c.visibility.map { $0 / 1000 },
            cloudCover: cloudCover,
            // `precipitation` is the sum of the preceding 15 minutes.
            precipitationIntensity: c.precipitation.map { $0 * 4 }
        )
    }

    /// Compares pressure now with three hours ago (±1 hPa is considered steady).
    static func pressureTrend(hours: [HourlyForecast], now: Date, currentPressure: Double?) -> PressureTrend {
        guard let pressureNow = currentPressure ?? hours.last(where: { $0.date <= now })?.pressure else {
            return .unknown
        }
        let target = now.addingTimeInterval(-3 * 3600)
        guard let earlier = hours
            .filter({ $0.pressure != nil })
            .min(by: { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }),
            abs(earlier.date.timeIntervalSince(target)) <= 3600,
            let pressureBefore = earlier.pressure else {
            return .unknown
        }
        let delta = pressureNow - pressureBefore
        if delta >= 1 { return .rising }
        if delta <= -1 { return .falling }
        return .steady
    }

    // MARK: Hourly

    static func hourly(from h: OMHourly) -> [HourlyForecast] {
        var indexByTime: [Int: Int] = [:]
        for (index, time) in h.time.enumerated() {
            indexByTime[Int(time)] = index
        }

        var result: [HourlyForecast] = []
        result.reserveCapacity(h.time.count)
        for (index, time) in h.time.enumerated() {
            guard let temperature = h.temperature.value(at: index) else { continue }
            // Values describing the hour [time, time + 1h) are reported at time + 1h.
            let periodIndex = indexByTime[Int(time) + 3600] ?? index
            let precipitation = h.precipitation.value(at: periodIndex)
            let snowfall = h.snowfall.value(at: periodIndex)
            let codeValue = h.weatherCode.value(at: periodIndex) ?? h.weatherCode.value(at: index)
            let code = codeValue.map { Int($0) }
            let cloudCover = h.cloudCover.value(at: periodIndex).map { $0 / 100 }
            let windSpeed = h.windSpeed.value(at: index)
            let condition = SkyCondition(wmoCode: code ?? 3, cloudCover: cloudCover, windSpeedKmh: windSpeed)
            let kind = precipitationKind(code: code, snowfall: snowfall, precipitation: precipitation)

            result.append(HourlyForecast(
                date: Date(timeIntervalSince1970: time),
                condition: condition,
                isDaylight: (h.isDay.value(at: index) ?? 1) > 0.5,
                temperature: temperature,
                apparentTemperature: h.apparentTemperature.value(at: index),
                humidity: h.relativeHumidity.value(at: index).map { $0 / 100 },
                dewPoint: h.dewPoint.value(at: index),
                precipitationChance: h.precipitationProbability.value(at: periodIndex).map { $0 / 100 },
                precipitationAmount: precipitation,
                snowfallAmount: snowfall,
                precipitationKind: (precipitation ?? 0) > 0 || condition.isPrecipitation ? kind : .none,
                windSpeed: windSpeed,
                windGust: h.windGusts.value(at: index),
                windDirection: h.windDirection.value(at: index),
                uvIndex: h.uvIndex.value(at: index),
                cloudCover: h.cloudCover.value(at: index).map { $0 / 100 },
                visibility: h.visibility.value(at: index).map { $0 / 1000 },
                pressure: h.pressure.value(at: index)
            ))
        }
        return result
    }

    // MARK: Daily

    /// Splits daily data into forecast days (today onwards) and past precipitation totals.
    static func daily(from d: OMDaily, timeZone: TimeZone, now: Date) -> ([DailyForecast], [PrecipitationSample]) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)

        var days: [DailyForecast] = []
        var past: [PrecipitationSample] = []
        for (index, time) in d.time.enumerated() {
            let date = Date(timeIntervalSince1970: time)
            if date < today {
                if let amount = d.precipitationSum.value(at: index) {
                    past.append(PrecipitationSample(date: date, amount: amount, snowfall: d.snowfallSum.value(at: index)))
                }
                continue
            }
            guard let high = d.temperatureMax.value(at: index), let low = d.temperatureMin.value(at: index) else { continue }
            let code = d.weatherCode.value(at: index).map { Int($0) }
            let precipitation = d.precipitationSum.value(at: index)
            let snowfall = d.snowfallSum.value(at: index)
            let condition = SkyCondition(wmoCode: code ?? 3, windSpeedKmh: nil)
            days.append(DailyForecast(
                date: date,
                condition: condition,
                high: high,
                low: low,
                apparentHigh: d.apparentTemperatureMax.value(at: index),
                apparentLow: d.apparentTemperatureMin.value(at: index),
                precipitationChance: d.precipitationProbabilityMax.value(at: index).map { $0 / 100 },
                precipitationAmount: precipitation,
                snowfallAmount: snowfall,
                precipitationHours: d.precipitationHours.value(at: index),
                precipitationKind: precipitationKind(code: code, snowfall: snowfall, precipitation: precipitation),
                sunrise: d.sunrise.value(at: index).map { Date(timeIntervalSince1970: $0) },
                sunset: d.sunset.value(at: index).map { Date(timeIntervalSince1970: $0) },
                uvIndexMax: d.uvIndexMax.value(at: index),
                windSpeedMax: d.windSpeedMax.value(at: index),
                windGustMax: d.windGustsMax.value(at: index),
                windDirectionDominant: d.windDirectionDominant.value(at: index)
            ))
        }
        return (days, past)
    }

    // MARK: Next hour (15-minute data)

    static func minutely(from m: OMMinutely15, now: Date) -> NextHourForecast? {
        var samples: [MinutePrecipitation] = []
        for (index, time) in m.time.enumerated() {
            // Each value is the sum of the preceding 15 minutes.
            let start = Date(timeIntervalSince1970: time - 900)
            guard start > now.addingTimeInterval(-1800), start < now.addingTimeInterval(3 * 3600) else { continue }
            guard let precipitation = m.precipitation.value(at: index) else { continue }
            let snowfall = m.snowfall.value(at: index)
            let code = m.weatherCode.value(at: index).map { Int($0) }
            let kind = precipitation > 0 ? precipitationKind(code: code, snowfall: snowfall, precipitation: precipitation) : .none
            samples.append(MinutePrecipitation(date: start, intensity: precipitation * 4, chance: nil, kind: kind))
        }
        guard !samples.isEmpty else { return nil }
        return NextHourForecast(minutes: samples, resolution: 900)
    }

    // MARK: History

    static func precipitationHistory(hourly: OMHourly?, pastDays: [PrecipitationSample], now: Date) -> PrecipitationHistory? {
        var hours: [PrecipitationSample] = []
        if let hourly {
            for (index, time) in hourly.time.enumerated() where time <= now.timeIntervalSince1970 {
                guard let amount = hourly.precipitation.value(at: index) else { continue }
                // Value at `time` covers the preceding hour.
                hours.append(PrecipitationSample(
                    date: Date(timeIntervalSince1970: time - 3600),
                    amount: amount,
                    snowfall: hourly.snowfall.value(at: index)
                ))
            }
        }
        guard !hours.isEmpty || !pastDays.isEmpty else { return nil }
        return PrecipitationHistory(hourly: hours, daily: pastDays)
    }

    // MARK: Helpers

    static func precipitationKind(code: Int?, snowfall: Double?, precipitation: Double?) -> PrecipitationKind {
        if let code {
            switch code {
            case 56, 57, 66, 67: return .sleet
            case 71...77, 85, 86: return .snow
            case 96, 99: return .hail
            case 51...65, 80...82, 95: return .rain
            default: break
            }
        }
        if let snowfall, snowfall > 0 {
            // Snow reported in cm; liquid equivalent roughly 1/10 when all precipitation is snow.
            if let precipitation, precipitation > snowfall * 0.2 { return .mixed }
            return .snow
        }
        if let precipitation, precipitation > 0 { return .rain }
        return .none
    }

    static func summary(from response: OMForecastResponse, locationID: String, now: Date) -> LocationWeatherSummary? {
        guard let c = response.current, let temperature = c.temperature else { return nil }
        let cloudCover = c.cloudCover.map { $0 / 100 }
        let condition = SkyCondition(wmoCode: c.weatherCode.map { Int($0) } ?? 3, cloudCover: cloudCover, windSpeedKmh: c.windSpeed)
        return LocationWeatherSummary(
            locationID: locationID,
            fetchedAt: now,
            timeZoneIdentifier: response.timezone ?? TimeZone.current.identifier,
            temperature: temperature,
            apparentTemperature: c.apparentTemperature,
            condition: condition,
            isDaylight: (c.isDay ?? 1) > 0.5,
            high: response.daily?.temperatureMax.value(at: 0),
            low: response.daily?.temperatureMin.value(at: 0),
            precipitationChance: response.daily?.precipitationProbabilityMax.value(at: 0).map { $0 / 100 },
            source: .openMeteo
        )
    }

    static func airQuality(from response: OMAirQualityResponse) -> AirQuality? {
        guard let c = response.current else { return nil }
        var pollutants: [PollutantReading] = []
        func add(_ pollutant: Pollutant, _ concentration: Double?, _ us: Double?, _ eu: Double?) {
            guard let concentration else { return }
            pollutants.append(PollutantReading(pollutant: pollutant, concentration: concentration, usAQI: us, europeanAQI: eu))
        }
        add(.pm2_5, c.pm2_5, c.usAQIPM2_5, c.europeanAQIPM2_5)
        add(.pm10, c.pm10, c.usAQIPM10, c.europeanAQIPM10)
        add(.ozone, c.ozone, c.usAQIOzone, c.europeanAQIOzone)
        add(.nitrogenDioxide, c.nitrogenDioxide, c.usAQINitrogenDioxide, c.europeanAQINitrogenDioxide)
        add(.sulphurDioxide, c.sulphurDioxide, c.usAQISulphurDioxide, c.europeanAQISulphurDioxide)
        add(.carbonMonoxide, c.carbonMonoxide, c.usAQICarbonMonoxide, nil)

        let pollenValues: [(PollenType, Double?)] = [
            (.alder, c.alderPollen), (.birch, c.birchPollen), (.grass, c.grassPollen),
            (.mugwort, c.mugwortPollen), (.olive, c.olivePollen), (.ragweed, c.ragweedPollen),
        ]
        let pollen = pollenValues.compactMap { type, value in value.map { PollenReading(type: type, concentration: $0) } }

        var hourly: [AQIForecastPoint] = []
        if let h = response.hourly {
            for (index, time) in h.time.enumerated() {
                let us = h.usAQI.value(at: index)
                let eu = h.europeanAQI.value(at: index)
                guard us != nil || eu != nil else { continue }
                hourly.append(AQIForecastPoint(date: Date(timeIntervalSince1970: time), usAQI: us, europeanAQI: eu))
            }
        }

        guard c.usAQI != nil || c.europeanAQI != nil || !pollutants.isEmpty else { return nil }
        return AirQuality(
            date: Date(timeIntervalSince1970: c.time),
            usAQI: c.usAQI,
            europeanAQI: c.europeanAQI,
            pollutants: pollutants,
            pollen: pollen,
            dust: c.dust,
            hourly: hourly
        )
    }
}
