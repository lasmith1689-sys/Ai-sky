import AiSkyKit
import SwiftUI

// Liquid: the Apple-style option. White type on the condition sky, sections as iOS 26 Liquid
// Glass cards and the system Liquid Glass tab bar.

/// Soft cloud shapes drifting in the sky gradient, as in the mockup.
struct LiquidClouds: View {
    let condition: SkyCondition
    let isDaylight: Bool

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width / 390
            // Bright clouds belong to a partly cloudy sky; on gray skies they would wash out the
            // white type, so they fade to a faint texture.
            let strength = LiquidGlass.cloudStrength(for: condition, isDaylight: isDaylight)
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.white.opacity(0.55 * strength))
                    .frame(width: 300 * w, height: 120 * w)
                    .blur(radius: 34)
                    .offset(x: -60 * w, y: 150 * w)
                Capsule()
                    .fill(Color.white.opacity(0.42 * strength))
                    .frame(width: 280 * w, height: 110 * w)
                    .blur(radius: 38)
                    .offset(x: 170 * w, y: 90 * w)
                Capsule()
                    .fill(Palette.color(hex: 0xFFF4E4, opacity: 0.45 * strength))
                    .frame(width: 360 * w, height: 160 * w)
                    .blur(radius: 46)
                    .offset(x: 40 * w, y: 520 * w)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension ForecastContext {
    /// White at the mockup's softer opacity on blue day skies; brighter on gray skies and at
    /// night, where the softer values fall under 4.5:1 (see `LiquidGlass`).
    func skyInk(_ blueSky: Double, gray: Double) -> Color {
        .white.opacity(tokens.brightSecondaryText ? gray : blueSky)
    }
}

/// White line icon for a condition, warm for sun, as in the mockup.
struct LiquidConditionIcon: View {
    let condition: SkyCondition
    var isDaylight = true

    var body: some View {
        let sunny = isDaylight && (condition.family == .clear || condition == .hot)
        OutlineConditionIcon(condition, isDaylight: isDaylight)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(sunny ? Palette.color(hex: 0xFFE7A3) : .white)
    }
}

struct LiquidHero: View {
    let context: ForecastContext

    var body: some View {
        let current = context.current
        let formatter = context.formatter
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if context.location.isCurrentLocation {
                    Image(systemName: "location.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(context.location.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.footnote.weight(.medium))
                .foregroundStyle(context.skyInk(0.78, gray: 1))
                .padding(.top, 2)
            Text(formatter.temperature(current.temperature))
                .font(.system(size: 124, weight: .thin))
                .tracking(-5)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())
                .cssLineHeight(1, size: 124, face: .system(.thin))
                .padding(.leading, 26) // optically center, ignoring the degree sign
                .padding(.top, 10)
                .accessibilityLabel("Temperature \(formatter.temperature(current.temperature, includeUnit: true))")
            Text(current.condition.description)
                .font(.title3.weight(.medium))
                .padding(.top, 2)
            Text(rangeLine)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(context.skyInk(0.86, gray: 1))
                .padding(.top, 3)
            if !context.window.isPrecipitating,
               let comparison = YesterdayComparison.text(for: context.snapshot, now: context.now, formatter: formatter) {
                Text(comparison)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(context.skyInk(0.8, gray: 1))
                    .padding(.top, 8)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .background {
            // Over the bright clouds of a blue day sky, a soft glow of the sky's own deeper top
            // color sits behind the hero so its white type keeps 4.5:1 (see `LiquidGlass`). It
            // reaches above the place name so the small top lines sit in its full strength.
            if context.tokens.heroScrim > 0 {
                Ellipse()
                    .fill(context.tokens.heroScrimColor.opacity(context.tokens.heroScrim))
                    .padding(.horizontal, -28)
                    .padding(.top, -56)
                    .padding(.bottom, -16)
                    .blur(radius: 32)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private var subtitle: String {
        let time = context.formatter.time(context.now, timeZone: context.timeZone)
        return context.location.isCurrentLocation ? "My Location · \(time)" : time
    }

    private var rangeLine: String {
        let formatter = context.formatter
        var parts = ["Feels \(formatter.temperature(context.current.apparentTemperature))"]
        if let today = context.today {
            parts.append("H \(formatter.temperature(today.high))  L \(formatter.temperature(today.low))")
        }
        return parts.joined(separator: "  ·  ")
    }
}

struct LiquidNextHour: View {
    let context: ForecastContext

    var body: some View {
        let window = context.window
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: window.isPrecipitating ? symbol(window) : "cloud")
                    .font(.system(size: 17, weight: .regular))
                Text(window.liquidTitle)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 6)
                if let detail = window.liquidDetail(clock: context.shortClock) {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(context.skyInk(0.8, gray: 0.92))
                        .lineLimit(1)
                }
            }
            if let forecast = context.snapshot.nextHour, window.state != .unavailable {
                MinutePrecipitationChart(forecast: forecast, now: context.now, showsGuides: false, showsAxis: false, tint: .white)
                    .frame(height: 56)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.white.opacity(0.35)).frame(height: 1)
                    }
                    .opacity(window.isPrecipitating ? 1 : 0.7)
                    .padding(.top, 12)
                HStack {
                    ForEach(["Now", "15m", "30m", "45m", "60m"], id: \.self) { label in
                        Text(label)
                        if label != "60m" { Spacer(minLength: 0) }
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(context.skyInk(0.72, gray: 0.82))
                .padding(.top, 6)
                if let resolution = context.nextHourResolution {
                    Text(resolution)
                        .font(.caption2)
                        .foregroundStyle(context.skyInk(0.72, gray: 0.82))
                        .padding(.top, 4)
                }
                if let rate = context.snapshot.current.precipitationIntensity, rate >= 0.05 {
                    Text("Now: \(PrecipitationIntensity(millimetersPerHour: rate).displayName.lowercased()) \(context.snapshot.current.condition.precipitationKind.noun), \(context.formatter.precipitationRate(rate))")
                        .font(.caption)
                        .foregroundStyle(context.skyInk(0.8, gray: 0.92))
                        .padding(.top, 6)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lookSurface(context.tokens, radius: 26)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(context.nextHourSpoken)
    }

    private func symbol(_ window: NextHourWindow) -> String {
        switch window.kind {
        case .snow: return "cloud.snow"
        case .sleet, .mixed, .hail: return "cloud.sleet"
        default: return window.intensity >= .moderate ? "cloud.heavyrain" : "cloud.rain"
        }
    }
}

/// Hour columns with sunrise and sunset slotted in, like Apple Weather.
struct LiquidHourly: View {
    let context: ForecastContext

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(items) { item in
                    column(item)
                        .containerRelativeFrame(.horizontal, count: 6, spacing: 0)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .lookSurface(context.tokens, radius: 26)
    }

    private var items: [ForecastHourItem] { context.hourItems() }

    @ViewBuilder
    private func column(_ item: ForecastHourItem) -> some View {
        switch item {
        case .hour(let hour):
            let chance = hour.precipitationChance ?? 0
            VStack(spacing: 7) {
                Text(context.isNow(hour) ? "Now" : context.formatter.hour(hour.date, timeZone: context.timeZone))
                    .font(.footnote.weight(.semibold))
                LiquidConditionIcon(condition: hour.condition, isDaylight: hour.isDaylight)
                    .font(.system(size: 21, weight: .light))
                    .frame(height: 26)
                Text(chance >= 0.15 ? context.formatter.chance(chance) : " ")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(context.tokens.rainText)
                Text(context.temperature(hour.temperature))
                    .font(.title3.weight(.medium))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(context.isNow(hour) ? "Now" : context.formatter.hour(hour.date, timeZone: context.timeZone)): \(context.spokenTemperature(hour.temperature)), \(hour.condition.description)\(chance >= 0.15 ? ", \(context.formatter.percent(chance)) chance of precipitation" : "")")
        case .sun(let date, let rising):
            VStack(spacing: 7) {
                Text(context.shortClock(date))
                    .font(.footnote.weight(.semibold))
                Image(systemName: rising ? "sunrise" : "sunset")
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(context.tokens.sun)
                    .frame(height: 26)
                Text(rising ? "Sunrise" : "Sunset")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.color(hex: 0xFFE2BD))
                Text(context.temperature(context.snapshot.conditions(at: date).temperature))
                    .font(.title3.weight(.medium))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(rising ? "Sunrise" : "Sunset") at \(context.formatter.time(date, timeZone: context.timeZone)), \(context.spokenTemperature(context.temperature(at: date)))")
        }
    }
}

struct LiquidDaily: View {
    let context: ForecastContext

    var body: some View {
        let days = context.days()
        let rangeLow = days.map(\.low).min() ?? 0
        let rangeHigh = days.map(\.high).max() ?? 1
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title: "\(days.count)-Day Forecast", systemImage: "calendar")
            Text(ForecastNarrator.weekSummary(days: days, now: context.now, timeZone: context.timeZone, formatter: context.formatter))
                .font(.subheadline)
                .foregroundStyle(context.skyInk(0.9, gray: 1))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.bottom, 4)
            ForEach(days) { day in
                Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1)
                Button {
                    context.onSelectDay(day)
                } label: {
                    row(day, rangeLow: rangeLow, rangeHigh: rangeHigh)
                }
                .buttonStyle(.plain)
            }
            Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1)
            Button(action: context.onTimeMachine) {
                CardLinkRow(title: "Time Machine", systemImage: "clock.arrow.circlepath", detail: "Any date since 1940")
                    .padding(.top, 8)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .lookSurface(context.tokens, radius: 26)
    }

    private func row(_ day: DailyForecast, rangeLow: Double, rangeHigh: Double) -> some View {
        let label = context.formatter.dayLabel(day.date, timeZone: context.timeZone, now: context.now)
        let today = context.isToday(day)
        return HStack(spacing: 12) {
            Text(label)
                .font(.callout.weight(.semibold))
                .frame(width: 84, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            VStack(spacing: 0) {
                LiquidConditionIcon(condition: day.condition)
                    .font(.system(size: 19, weight: .light))
                if let chance = day.precipitationChance, chance >= 0.15 {
                    Text(context.formatter.chance(chance))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(context.tokens.rainText)
                }
            }
            .frame(width: 32)
            Text(context.temperature(day.low))
                .font(.callout)
                .foregroundStyle(context.skyInk(0.72, gray: 0.82))
                .frame(width: 36, alignment: .trailing)
            TemperatureRangeBar(low: day.low, high: day.high, rangeLow: rangeLow, rangeHigh: rangeHigh, current: today ? context.current.temperature : nil, trackColor: .white.opacity(0.2))
            Text(context.temperature(day.high))
                .font(.callout.weight(.semibold))
                .frame(width: 36, alignment: .trailing)
        }
        .frame(minHeight: 50)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(day.condition.description), high \(context.spokenTemperature(day.high)), low \(context.spokenTemperature(day.low))")
    }
}
