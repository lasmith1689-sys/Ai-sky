import AiSkyKit
import SwiftUI

// Chroma '74: big color blocks on cream. A navy hero with a huge temperature and the retro
// stripe, a cobalt next-hour block, color-coded hourly tiles and a pill tab bar.

private let cream = ChromaPalette.cream
private let navy = ChromaPalette.navy

struct ChromaHero: View {
    @Environment(\.lookTokens) private var t
    let context: ForecastContext

    var body: some View {
        let current = context.current
        let window = context.window
        let mono = t.face(.label)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if context.location.isCurrentLocation {
                            Image(systemName: "location.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .accessibilityHidden(true)
                        }
                        Text(context.location.name.uppercased())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    if context.location.isCurrentLocation {
                        Text("MY LOCATION")
                            .font(mono.font(10))
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(context.formatter.time(context.now, timeZone: context.timeZone).uppercased())
            }
            .font(mono.font(12))
            .tracking(2)
            .foregroundStyle(cream.opacity(0.72))

            Text(context.temperature(current.temperature))
                .font(t.font(.display, 150, relativeTo: .largeTitle))
                .tracking(-8)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .cssLineHeight(0.9, size: 150, face: t.display)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .padding(.top, 14)
                .accessibilityLabel("Temperature \(context.formatter.temperature(current.temperature, includeUnit: true))")
            Text(sentenceCase(current.condition.description))
                .font(t.font(.headline, 25))
                .tracking(-0.4)
                .foregroundStyle(ChromaPalette.mustard)
                .padding(.top, 10)
            Text(window.status(long: true) ?? "Dry for the next hour")
                .font(t.font(.textMedium, 16))
                .foregroundStyle(cream.opacity(window.isPrecipitating ? 1 : 0.8))
                .padding(.top, 2)
            HStack(spacing: 18) {
                Text("Feels \(context.temperature(current.apparentTemperature))")
                if let today = context.today {
                    Text("Hi \(context.temperature(today.high))")
                    Text("Lo \(context.temperature(today.low))")
                }
            }
            .font(mono.font(12))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(cream.opacity(0.8))
            .padding(.top, 16)
            if let headline = context.headline {
                Text(headline)
                    .font(t.font(.text, 15))
                    .foregroundStyle(cream.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
        .foregroundStyle(cream)
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(navy)
        .overlay(alignment: .bottom) { RetroStripe() }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
}

/// Orange, mustard and green bands.
struct RetroStripe: View {
    var band: CGFloat = 7

    var body: some View {
        VStack(spacing: 0) {
            ChromaPalette.orange.frame(height: band)
            ChromaPalette.mustard.frame(height: band)
            ChromaPalette.green.frame(height: band)
        }
        .accessibilityHidden(true)
    }
}

struct ChromaNextHour: View {
    @Environment(\.lookTokens) private var t
    let context: ForecastContext

    var body: some View {
        let window = context.window
        let mono = t.face(.label)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.chromaTitle(clock: context.shortClock))
                    .font(t.font(.headline, 18))
                    .tracking(-0.2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let word = window.intensityWord {
                    Text(word.uppercased())
                        .font(mono.font(11))
                        .foregroundStyle(cream.opacity(0.75))
                }
            }
            if let forecast = context.snapshot.nextHour, window.state != .unavailable {
                MinuteBars(forecast: forecast, now: context.now, wetColor: cream, dryColor: cream.opacity(0.28), dryHeight: 3, cornerRadius: 3)
                    .frame(height: 42)
                    .padding(.top, 12)
                HStack {
                    ForEach(["Now", ":15", ":30", ":45", ":60"], id: \.self) { label in
                        Text(label)
                        if label != ":60" { Spacer(minLength: 0) }
                    }
                }
                .font(mono.font(10))
                .textCase(.uppercase)
                .foregroundStyle(cream.opacity(0.72))
                .padding(.top, 7)
                if let rate = context.precipitationRateLine {
                    Text(rate)
                        .font(t.font(.textMedium, 14))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
                if let resolution = context.nextHourResolution {
                    Text(resolution.uppercased())
                        .font(mono.font(10))
                        .tracking(1)
                        .foregroundStyle(cream.opacity(0.8))
                        .padding(.top, 6)
                }
            }
        }
        .foregroundStyle(cream)
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChromaPalette.cobalt, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(context.nextHourSpoken)
    }
}

/// Color-coded hour tiles: mustard by day, green when it's wet, navy at night, and an
/// orange-rimmed sand tile for sunrise and sunset.
struct ChromaHourly: View {
    @Environment(\.lookTokens) private var t
    let context: ForecastContext

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(context.hourItems()) { item in
                    tile(item)
                        .containerRelativeFrame(.horizontal, count: 6, spacing: 6)
                }
            }
        }
    }

    @ViewBuilder
    private func tile(_ item: ForecastHourItem) -> some View {
        switch item {
        case .hour(let hour): hourTile(hour)
        case .sun(let date, let rising): sunTile(date, rising: rising)
        }
    }

    private func hourTile(_ hour: HourlyForecast) -> some View {
        let chance = hour.precipitationChance ?? 0
        let wet = chance >= 0.5 || hour.condition.isPrecipitation
        let fill: Color = wet ? ChromaPalette.green : (hour.isDaylight ? ChromaPalette.mustard : navy)
        let ink: Color = !wet && hour.isDaylight ? navy : cream
        let mono = t.face(.label)
        let now = context.isNow(hour)
        return VStack(spacing: 0) {
            Text(now ? "NOW" : compactHour(hour.date))
                .font(LookFace.custom("DMMono-Medium").font(11))
            Spacer(minLength: 4)
            OutlineConditionIcon(hour.condition, isDaylight: hour.isDaylight)
                .font(.system(size: 15, weight: .medium))
                .frame(height: 18)
            Spacer(minLength: 4)
            Text(context.temperature(hour.temperature))
                .font(t.font(.headline, 23))
                .tracking(-0.5)
            Spacer(minLength: 4)
            Text("\(Int((chance * 100).rounded()))%")
                .font(chance >= 0.2 ? LookFace.custom("DMMono-Medium").font(10) : mono.font(10))
                .opacity(chance >= 0.2 ? 1 : 0.6)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .foregroundStyle(ink)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 124)
        .background(fill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(now ? "Now" : context.formatter.hour(hour.date, timeZone: context.timeZone)): \(context.spokenTemperature(hour.temperature)), \(hour.condition.description), \(context.formatter.percent(chance)) chance of precipitation")
    }

    private func sunTile(_ date: Date, rising: Bool) -> some View {
        VStack(spacing: 0) {
            Text(compactClock(date))
                .font(LookFace.custom("DMMono-Medium").font(11))
            Spacer(minLength: 4)
            Image(systemName: rising ? "sunrise" : "sunset")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ChromaPalette.orange)
                .frame(height: 18)
            Spacer(minLength: 4)
            Text(context.temperature(context.temperature(at: date)))
                .font(t.font(.headline, 23))
                .tracking(-0.5)
            Spacer(minLength: 4)
            Text(rising ? "RISE" : "SET")
                .font(LookFace.custom("DMMono-Medium").font(10))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .foregroundStyle(navy)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 124)
        .background(ChromaPalette.sand, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(ChromaPalette.orange, lineWidth: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rising ? "Sunrise" : "Sunset") at \(context.formatter.time(date, timeZone: context.timeZone)), \(context.spokenTemperature(context.temperature(at: date)))")
    }

    /// "6:42A" (or "06:42" on a 24-hour phone).
    private func compactClock(_ date: Date) -> String {
        context.formatter.time(date, timeZone: context.timeZone)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: " PM", with: "P")
            .replacingOccurrences(of: " AM", with: "A")
    }

    /// "4P", "11A" (or "16" on a 24-hour phone).
    private func compactHour(_ date: Date) -> String {
        context.formatter.hour(date, timeZone: context.timeZone)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: " PM", with: "P")
            .replacingOccurrences(of: " AM", with: "A")
    }
}

struct ChromaDaily: View {
    @Environment(\.lookTokens) private var t
    let context: ForecastContext

    var body: some View {
        let days = context.days()
        let rangeLow = days.map(\.low).min() ?? 0
        let rangeHigh = days.map(\.high).max() ?? 1
        VStack(spacing: 0) {
            Text(context.weekSummary)
                .font(t.font(.text, 15))
                .foregroundStyle(t.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                .padding(.bottom, 10)
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
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
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func row(_ day: DailyForecast, rangeLow: Double, rangeHigh: Double) -> some View {
        let label = context.formatter.dayLabel(day.date, timeZone: context.timeZone, now: context.now)
        let mono = t.face(.label)
        let chance = day.precipitationChance ?? 0
        return HStack(spacing: 10) {
            Text(label)
                .font(t.font(.headline, 16))
                .frame(width: 84, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            OutlineConditionIcon(day.condition)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 22)
            Text(chance >= 0.15 ? "\(Int((chance * 100).rounded()))%" : "")
                .font(LookFace.custom("DMMono-Medium").font(11))
                .foregroundStyle(t.rainText)
                .frame(width: 30, alignment: .leading)
            Text(context.degrees(day.low))
                .font(mono.font(13))
                .foregroundStyle(t.ink2)
                .frame(width: 28, alignment: .leading)
            LookRangeBar(
                low: day.low, high: day.high, rangeLow: rangeLow, rangeHigh: rangeHigh,
                height: 8, fill: segmentColor(high: day.high), track: t.track
            )
            Text(context.degrees(day.high))
                .font(LookFace.custom("DMMono-Medium").font(13))
                .frame(width: 28, alignment: .trailing)
        }
        .foregroundStyle(t.ink)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(day.condition.description), high \(context.spokenTemperature(day.high)), low \(context.spokenTemperature(day.low))\(chance >= 0.15 ? ", \(context.formatter.percent(chance)) chance of precipitation" : "")")
    }

    /// Warm days orange, mild mustard, cool green, cold cobalt.
    private func segmentColor(high: Double) -> Color {
        switch high {
        case 21...: return ChromaPalette.orange
        case 12..<21: return ChromaPalette.mustard
        case 2..<12: return ChromaPalette.green
        default: return ChromaPalette.cobalt
        }
    }
}
