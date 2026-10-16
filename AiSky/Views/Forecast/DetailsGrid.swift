import AiSkyKit
import SwiftUI

/// Grid of current-condition details.
struct DetailsGrid: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lookTokens) private var t
    let snapshot: WeatherSnapshot
    let now: Date

    var body: some View {
        let formatter = model.formatter
        let current = snapshot.conditions(at: now)
        let today = snapshot.day(containing: now)
        let gap: CGFloat = t.surfaceStyle == .hairline ? 20 : (t.look == .chroma ? 10 : 12)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: gap), GridItem(.flexible(), spacing: gap)], spacing: t.surfaceStyle == .hairline ? 8 : gap) {
            DetailTile(
                title: "Feels Like",
                systemImage: "thermometer.medium",
                value: formatter.temperature(current.apparentTemperature),
                detail: FeelsLikeInsight.explanation(
                    temperature: current.temperature,
                    apparentTemperature: current.apparentTemperature,
                    humidity: current.humidity,
                    windSpeed: current.windSpeed,
                    isDaylight: current.isDaylight
                )
            )

            if let humidity = current.humidity {
                DetailTile(
                    title: "Humidity",
                    systemImage: "humidity.fill",
                    value: formatter.percent(humidity),
                    detail: HumidityInsight.dewPointText(current.dewPoint, formatter: formatter)
                )
            }

            if let speed = current.windSpeed {
                DetailTile(title: "Wind", systemImage: "wind", value: formatter.windSpeed(speed), detail: windDetail(current, formatter), tone: .navy) {
                    if let direction = current.windDirection {
                        WindCompass(direction: direction)
                            .frame(width: 64, height: 64)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            if let uv = current.uvIndex {
                let category = UVCategory(index: uv)
                DetailTile(
                    title: "UV Index",
                    systemImage: "sun.max.fill",
                    value: "\(Int(uv.rounded())) \(category.name)",
                    detail: UVCategory.protectionAdvice(hours: snapshot.hourly, day: now, timeZone: snapshot.timeZone, formatter: formatter),
                    tone: .mustard
                ) {
                    ScaleBar(
                        colors: [UVCategory.low, .moderate, .high, .veryHigh, .extreme].map(Palette.uv),
                        position: min(1, uv / 11)
                    )
                }
            }

            if let today, let sunrise = today.sunrise, let sunset = today.sunset {
                let beforeSunrise = now < sunrise
                let afterSunset = now > sunset
                let nextEvent = beforeSunrise ? sunrise : sunset
                DetailTile(
                    title: afterSunset || beforeSunrise ? "Sunrise" : "Sunset",
                    systemImage: afterSunset || beforeSunrise ? "sunrise.fill" : "sunset.fill",
                    value: formatter.time(afterSunset ? nextSunrise ?? sunrise : nextEvent, timeZone: snapshot.timeZone),
                    detail: beforeSunrise || afterSunset
                        ? "Sunset: \(formatter.time(sunset, timeZone: snapshot.timeZone))"
                        : "Sunrise: \(formatter.time(sunrise, timeZone: snapshot.timeZone))",
                    tone: .cobalt
                ) {
                    SunArc(progress: sunProgress(sunrise: sunrise, sunset: sunset))
                        .frame(height: 38)
                }
            }

            if let pressure = current.pressure {
                DetailTile(
                    title: "Pressure",
                    systemImage: "gauge.with.dots.needle.33percent",
                    value: formatter.pressure(pressure),
                    detail: current.pressureTrend == .unknown ? nil : "\(current.pressureTrend.description) over the last 3 hours."
                ) {
                    if current.pressureTrend != .unknown {
                        Image(systemName: current.pressureTrend.symbolName)
                            .font(.title3.weight(.semibold))
                    }
                }
            }

            if let visibility = current.visibility {
                DetailTile(
                    title: "Visibility",
                    systemImage: "eye.fill",
                    value: formatter.visibility(visibility),
                    detail: VisibilityInsight.description(kilometers: visibility)
                )
            }

            if let cloudCover = current.cloudCover {
                DetailTile(
                    title: "Cloud Cover",
                    systemImage: "cloud.fill",
                    value: formatter.percent(cloudCover),
                    detail: current.condition.description
                )
            }

            let moon = MoonCalculator.moon(on: now)
            DetailTile(
                title: "Moon",
                systemImage: "moon.stars.fill",
                value: "\(Int((moon.illumination * 100).rounded()))%",
                detail: "\(moon.phase.name). Next full moon \(formatter.monthDay(moon.nextFullMoon, timeZone: snapshot.timeZone)).",
                tone: .green
            ) {
                Image(systemName: moon.phase.symbolName)
                    .font(.system(size: 34))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var nextSunrise: Date? {
        snapshot.daily.first { ($0.sunrise ?? .distantPast) > now }?.sunrise
    }

    private func sunProgress(sunrise: Date, sunset: Date) -> Double? {
        guard now >= sunrise, now <= sunset else { return nil }
        return now.timeIntervalSince(sunrise) / sunset.timeIntervalSince(sunrise)
    }

    private func windDetail(_ current: CurrentConditions, _ formatter: WeatherFormatter) -> String {
        var parts: [String] = []
        if let direction = current.windDirection {
            parts.append("From the \(WeatherFormatter.compassDirectionName(direction)).")
        }
        if let gust = current.windGust, gust > (current.windSpeed ?? 0) + 5 {
            parts.append("Gusts to \(formatter.windSpeed(gust)).")
        }
        return parts.joined(separator: " ")
    }
}

/// Compass rose with an arrow pointing where the wind is blowing to.
struct WindCompass: View {
    @Environment(\.lookTokens) private var t
    /// Direction the wind comes from, in degrees.
    let direction: Double

    var body: some View {
        ZStack {
            Circle().stroke(t.line.opacity(t.look == .liquid ? 1.4 : 1), lineWidth: 1.5)
            ForEach(Array(["N", "E", "S", "W"].enumerated()), id: \.offset) { index, letter in
                let angle = Double(index) * .pi / 2
                Text(letter)
                    .font(t.look == .liquid ? .system(size: 9, weight: .bold) : t.font(.label, 9, fixed: true))
                    .foregroundStyle(t.ink2)
                    .offset(x: sin(angle) * 24, y: -cos(angle) * 24)
            }
            Image(systemName: "location.north.fill")
                .font(.system(size: 20))
                .foregroundStyle(t.look == .instrument ? t.now : t.ink)
                .rotationEffect(.degrees(direction + 180))
        }
        .accessibilityLabel("Wind from \(WeatherFormatter.compassDirectionName(direction))")
    }
}

/// Arc showing the sun's position between sunrise and sunset.
struct SunArc: View {
    @Environment(\.lookTokens) private var t
    /// 0...1 between sunrise and sunset, or nil at night.
    let progress: Double?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let path = Path { path in
                path.move(to: CGPoint(x: 0, y: height))
                path.addQuadCurve(to: CGPoint(x: width, y: height), control: CGPoint(x: width / 2, y: -height * 0.9))
            }
            ZStack(alignment: .topLeading) {
                path.stroke(t.ink3, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                Rectangle()
                    .fill(t.line)
                    .frame(height: 1)
                    .offset(y: height)
                if let progress {
                    let u = min(max(progress, 0), 1)
                    // Point on the quadratic Bézier curve.
                    let x = width * u
                    let y = pow(1 - u, 2) * height + 2 * (1 - u) * u * (-height * 0.9) + pow(u, 2) * height
                    Circle()
                        .fill(t.look == .liquid ? Color.yellow : t.sun)
                        .shadow(color: (t.look == .liquid ? Color.yellow : t.sun).opacity(0.8), radius: 4)
                        .frame(width: 10, height: 10)
                        .offset(x: x - 5, y: y - 5)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
