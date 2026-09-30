import AiSkyKit
import SwiftUI

// Instrument: graphite panels read like a cockpit. The signature is the 270° range dial with an
// orange needle; labels are condensed caps; cobalt is rain, burnt orange is "now".

private let condensedMedium = LookFace.custom("BarlowCondensed-Medium")

/// Place and local time in condensed caps.
struct InstrumentHeader: View {
    @Environment(\.lookTokens) private var t
    let location: WeatherLocation
    let clock: String
    var clockLabel: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if location.isCurrentLocation {
                    Image(systemName: "location.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(t.ink2)
                        .accessibilityLabel("Current location")
                }
                Text(location.name)
                    .lookLabel(t, size: 13, color: t.ink, tracking: 3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityAddTraits(.isHeader)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            Text(clock)
                .lookLabel(t, size: 13, color: t.ink2, tracking: 2)
                .monospacedDigit()
                .lineLimit(1)
                .accessibilityLabel(clockLabel)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

struct InstrumentHero: View {
    let context: ForecastContext

    var body: some View {
        VStack(spacing: 6) {
            InstrumentHeader(
                location: context.location,
                clock: clockWithZone,
                clockLabel: "Local time \(context.formatter.time(context.now, timeZone: context.timeZone))"
            )
            RangeGaugeView(reading: RangeGaugeView.Reading(context: context))
                .frame(maxWidth: .infinity)
        }
    }

    /// "15:12 EDT".
    private var clockWithZone: String {
        let time = context.clock(context.now)
        guard let zone = context.timeZone.abbreviation(for: context.now), !zone.hasPrefix("GMT+"), !zone.hasPrefix("GMT-") else {
            return time
        }
        return "\(time) \(zone)"
    }
}

/// The signature element: a 270° dial with today's low-to-high arc, an orange needle at the
/// current temperature and the reading in the middle. Drawn in the mockup's 300 × 300 design
/// space and scaled as a whole, so it grows with Dynamic Type up to the screen width.
struct RangeGaugeView: View {
    struct Reading: Equatable {
        var current: Double
        var feelsLike: Double
        var low: Double
        var high: Double
        var unit: TemperatureUnit
        var condition: String
    }

    @Environment(\.lookTokens) private var t
    let reading: Reading

    @ScaledMetric(relativeTo: .body) private var scaledSize: CGFloat = 262
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var needleValue: Double?

    private var scale: GaugeScale {
        GaugeScale.fitting(low: reading.low, high: reading.high, current: reading.current, labelStep: reading.unit == .celsius ? 5 : 10)
    }

    var body: some View {
        let size = min(scaledSize, 330)
        let s = size / 300
        let scale = scale
        ZStack {
            GaugeDial(scale: scale, low: reading.low, high: reading.high, tokens: t)

            GaugeNeedle()
                .fill(t.now)
                .rotationEffect(.degrees(scale.angle(needleValue ?? scale.lower) - 270))
                .accessibilityHidden(true)

            Text(Self.number(reading.current))
                .font(t.font(.display, 92 * s, fixed: true))
                .tracking(-3 * s)
                .foregroundStyle(t.ink)
                .contentTransition(.numericText(value: reading.current))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .overlay(alignment: .topTrailing) {
                    Text(reading.unit.symbol)
                        .font(t.font(.text, 20 * s, fixed: true))
                        .foregroundStyle(t.ink2)
                        .fixedSize()
                        .alignmentGuide(.trailing) { $0[.leading] - 4 * s }
                        .alignmentGuide(.top) { $0[.top] - 18 * s }
                }
                .frame(maxWidth: 132 * s)
                .position(x: 146 * s, y: (172 - 0.36 * 92) * s)

            Text("Feels \(Self.number(reading.feelsLike))")
                .font(t.font(.label, 14 * s, fixed: true))
                .tracking(2.5 * s)
                .textCase(.uppercase)
                .foregroundStyle(t.ink2)
                .lineLimit(1)
                .position(x: 150 * s, y: (200 - 0.36 * 14) * s)

            Text(reading.condition)
                .font(t.font(.label, 15 * s, fixed: true))
                .tracking(2.5 * s)
                .textCase(.uppercase)
                .foregroundStyle(t.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: 290 * s)
                .position(x: 150 * s, y: (254 - 0.36 * 15) * s)

            Text("Range \(Self.number(reading.low)) · \(Self.number(reading.high))")
                .font(condensedMedium.font(13 * s, fixed: true))
                .tracking(2 * s)
                .textCase(.uppercase)
                .foregroundStyle(t.ink2)
                .lineLimit(1)
                .position(x: 150 * s, y: (274 - 0.36 * 13) * s)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .onAppear { moveNeedle(animated: !reduceMotion) }
        .onChange(of: reading) { _, _ in moveNeedle(animated: !reduceMotion) }
    }

    private func moveNeedle(animated: Bool) {
        if animated {
            if needleValue == nil { needleValue = scale.lower }
            withAnimation(.spring(response: 1.1, dampingFraction: 0.72).delay(0.1)) {
                needleValue = reading.current
            }
        } else {
            needleValue = reading.current
        }
    }

    private var accessibilityText: String {
        "\(Self.number(reading.current)) degrees, feels like \(Self.number(reading.feelsLike)). \(reading.condition). Today's range \(Self.number(reading.low)) to \(Self.number(reading.high))."
    }

    /// Rounded whole degrees without a "-0".
    static func number(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded == 0 ? "0" : String(rounded)
    }
}

extension RangeGaugeView.Reading {
    /// Today's reading in the user's units.
    init(context: ForecastContext) {
        let formatter = context.formatter
        let conditions = context.current
        let current = formatter.temperatureValue(conditions.temperature)
        self.init(
            current: current,
            feelsLike: formatter.temperatureValue(conditions.apparentTemperature),
            low: context.today.map { formatter.temperatureValue($0.low) } ?? current,
            high: context.today.map { formatter.temperatureValue($0.high) } ?? current,
            unit: formatter.units.temperature,
            condition: conditions.condition.description
        )
    }
}

/// Track, ticks, scale numbers and the low-to-high arc.
private struct GaugeDial: View {
    let scale: GaugeScale
    let low: Double
    let high: Double
    let tokens: LookTokens

    var body: some View {
        Canvas { context, size in
            let s = size.width / 300
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            func point(_ degrees: Double, _ radius: Double) -> CGPoint {
                let radians = degrees * .pi / 180
                return CGPoint(x: center.x + cos(radians) * radius * s, y: center.y + sin(radians) * radius * s)
            }

            // Sampled rather than addArc so the sweep direction is never ambiguous.
            func arc(from start: Double, to end: Double, radius: Double) -> Path {
                var path = Path()
                let steps = max(2, Int(abs(end - start) * 2))
                for step in 0...steps {
                    let angle = start + (end - start) * Double(step) / Double(steps)
                    if step == 0 {
                        path.move(to: point(angle, radius))
                    } else {
                        path.addLine(to: point(angle, radius))
                    }
                }
                return path
            }

            for tick in scale.ticks {
                let angle = scale.angle(tick.value)
                var path = Path()
                path.move(to: point(angle, tick.isMajor ? 100 : 105))
                path.addLine(to: point(angle, 110))
                context.stroke(
                    path,
                    with: .color(tick.isMajor ? tokens.ink3 : Palette.color(hex: 0x3A3F46)),
                    style: StrokeStyle(lineWidth: (tick.isMajor ? 2 : 1.4) * s, lineCap: .butt)
                )
            }

            let ring = StrokeStyle(lineWidth: 12 * s, lineCap: .round)
            context.stroke(
                arc(from: GaugeScale.startAngle, to: GaugeScale.startAngle + GaugeScale.sweep, radius: 116),
                with: .color(tokens.track), style: ring
            )
            let start = scale.angle(min(low, high))
            let end = max(scale.angle(max(low, high)), start + 0.5)
            context.stroke(arc(from: start, to: end, radius: 116), with: .color(tokens.ink), style: ring)

            for value in scale.labels {
                let label = Text(RangeGaugeView.number(value))
                    .font(tokens.font(.label, 13 * s, fixed: true))
                    .foregroundStyle(tokens.ink3)
                context.draw(label, at: point(scale.angle(value), 85), anchor: .center)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The needle pointing straight up (270°): a line crossing the ring with a dot at its tip,
/// rotated into place around the dial's center.
private struct GaugeNeedle: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 300
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        let width = 4 * s
        path.addRoundedRect(
            in: CGRect(x: center.x - width / 2, y: center.y - 124 * s, width: width, height: 30 * s),
            cornerSize: CGSize(width: width / 2, height: width / 2)
        )
        path.addEllipse(in: CGRect(x: center.x - 4 * s, y: center.y - 128 * s, width: 8 * s, height: 8 * s))
        return path
    }
}

/// Minute-by-minute bars with an orange "now" line, under a condensed header.
struct InstrumentNextHour: View {
    @Environment(\.lookTokens) private var t
    let context: ForecastContext

    var body: some View {
        let window = context.window
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Next Hour")
                    .lookLabel(t, size: 12, color: t.ink2, tracking: 2.2)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(window.instrumentHeader(clock: context.clock))
                    .lookLabel(t, size: 12, color: window.isPrecipitating ? t.rainText : t.ink3, tracking: 2.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if let forecast = context.snapshot.nextHour, window.state != .unavailable {
                MinuteBars(forecast: forecast, now: context.now, wetColor: t.rain, dryColor: t.line)
                    .frame(height: 46)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(t.now)
                            .frame(width: 2)
                            .offset(x: -6)
                    }
                    .padding(.top, 12)
                HStack {
                    ForEach(["Now", "15", "30", "45", "60"], id: \.self) { label in
                        Text(label)
                        if label != "60" { Spacer(minLength: 0) }
                    }
                }
                .lookLabel(t, size: 11, color: t.ink3, face: condensedMedium, tracking: 1.5)
                .padding(.top, 7)
            } else {
                Text("Minute-by-minute precipitation isn't available here.")
                    .font(t.font(.text, 14))
                    .foregroundStyle(t.ink2)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lookSurface(t, radius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next hour. \(NextHourSummarizer.summarize(context.snapshot.nextHour, now: context.now).text)")
    }
}

/// Stat tiles and the hourly strip.
struct InstrumentHourly: View {
    @Environment(\.lookTokens) private var t
    let context: ForecastContext

    var body: some View {
        VStack(spacing: 10) {
            InstrumentStatTiles(context: context)
            InstrumentHourStrip(context: context)
        }
    }
}

private struct InstrumentStatTiles: View {
    @Environment(\.lookTokens) private var t
    let context: ForecastContext

    var body: some View {
        let current = context.current
        let formatter = context.formatter
        HStack(spacing: 8) {
            if let speed = current.windSpeed {
                tile("Wind", formatter.windSpeed(speed, includeUnit: false),
                     current.windDirection.map { WeatherFormatter.compassDirection($0) },
                     spoken: formatter.wind(speed: speed, direction: current.windDirection))
            }
            if let humidity = current.humidity {
                tile("Humid", "\(Int((humidity * 100).rounded()))", "%", spoken: "Humidity \(formatter.percent(humidity))")
            }
            if let uv = current.uvIndex {
                let category = UVCategory(index: uv)
                tile("UV", "\(Int(uv.rounded()))", InstrumentAbbreviation.uv(category), spoken: "UV index \(Int(uv.rounded())), \(category.name)")
            }
            if let airQuality = context.snapshot.airQuality, let value = airQuality.index(for: context.settings.aqiScale) {
                let level = context.settings.aqiScale.level(for: value)
                tile("AQI", "\(Int(value.rounded()))", InstrumentAbbreviation.aqi(level), spoken: "Air quality \(Int(value.rounded())), \(level.name)")
            }
        }
    }

    private func tile(_ label: String, _ value: String, _ unit: String?, spoken: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .lookLabel(t, size: 10, color: t.ink2, tracking: 2)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(t.font(.number, 22))
                    .foregroundStyle(t.ink)
                if let unit {
                    Text(unit)
                        .font(t.font(.text, 12))
                        .foregroundStyle(t.ink2)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lookSurface(t, radius: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

/// 48 hours as columns: hour, temperature, a chance capsule and the chance. Six fit the card.
private struct InstrumentHourStrip: View {
    @Environment(\.lookTokens) private var t
    let context: ForecastContext

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(context.hours(48)) { hour in
                    column(hour)
                        .containerRelativeFrame(.horizontal, count: 6, spacing: 0)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .lookSurface(t, radius: 18)
    }

    private func column(_ hour: HourlyForecast) -> some View {
        let now = context.isNow(hour)
        let chance = hour.precipitationChance ?? 0
        return VStack(spacing: 6) {
            Text(now ? "Now" : context.hourLabel(hour.date))
                .lookLabel(t, size: 11, color: now ? t.now : t.ink2, tracking: 1.6)
            Text(context.temperature(hour.temperature))
                .font(t.font(.number, 20))
                .foregroundStyle(t.ink)
            ChanceCapsule(chance: chance, fill: t.rain, track: t.track)
            Text("\(Int((chance * 100).rounded()))")
                .font(condensedMedium.font(11))
                .foregroundStyle(chance >= 0.2 ? t.rainText : t.ink3)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(now ? "Now" : context.formatter.hour(hour.date, timeZone: context.timeZone)): \(context.temperature(hour.temperature)), \(hour.condition.description), \(context.formatter.percent(chance)) chance of precipitation")
    }
}

/// Ten days: condensed day names, line icons and cream range segments with an orange "now" dot.
struct InstrumentDaily: View {
    @Environment(\.lookTokens) private var t
    let context: ForecastContext

    var body: some View {
        let days = context.days()
        let rangeLow = days.map(\.low).min() ?? 0
        let rangeHigh = days.map(\.high).max() ?? 1
        VStack(alignment: .leading, spacing: 0) {
            Text("\(days.count) Day")
                .lookLabel(t, size: 12, color: t.ink2, tracking: 2.2)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            ForEach(days) { day in
                LookRule()
                Button {
                    context.onSelectDay(day)
                } label: {
                    row(day, rangeLow: rangeLow, rangeHigh: rangeHigh)
                }
                .buttonStyle(.plain)
            }
            LookRule()
            Button(action: context.onTimeMachine) {
                CardLinkRow(title: "Time Machine", systemImage: "clock.arrow.circlepath", detail: "Any date since 1940")
                    .padding(.top, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .lookSurface(t, radius: 18)
    }

    private func row(_ day: DailyForecast, rangeLow: Double, rangeHigh: Double) -> some View {
        let label = context.formatter.dayLabel(day.date, timeZone: context.timeZone, now: context.now)
        let today = context.isToday(day)
        return HStack(spacing: 10) {
            Text(label)
                .lookLabel(t, size: 13, color: today ? t.ink : t.ink2, tracking: 2)
                .frame(width: 74, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            OutlineConditionIcon(day.condition)
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(t.ink2)
                .frame(width: 24)
            Text(chanceText(day))
                .font(condensedMedium.font(12))
                .foregroundStyle(t.rainText)
                .frame(width: 30, alignment: .leading)
            Text(context.degrees(day.low))
                .font(t.font(.number, 16))
                .foregroundStyle(t.ink2)
                .frame(width: 26, alignment: .trailing)
            LookRangeBar(
                low: day.low, high: day.high, rangeLow: rangeLow, rangeHigh: rangeHigh,
                current: today ? context.current.temperature : nil,
                height: 4, fill: t.ink, track: t.track, marker: .dot(t.now, ring: t.surface)
            )
            Text(context.degrees(day.high))
                .font(t.font(.number, 16))
                .foregroundStyle(t.ink)
                .frame(width: 26, alignment: .trailing)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(day.condition.description), high \(context.temperature(day.high)), low \(context.temperature(day.low))")
    }

    private func chanceText(_ day: DailyForecast) -> String {
        guard let chance = day.precipitationChance, chance >= 0.15 else { return "" }
        return "\(Int((chance * 100).rounded()))%"
    }
}
