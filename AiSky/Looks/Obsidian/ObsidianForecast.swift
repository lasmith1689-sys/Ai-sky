import AiSkyKit
import SwiftUI

// Obsidian: true black, hairline rules instead of cards, a huge ultralight temperature and mono
// caps labels. One accent, #7CC4FF, and it only ever means rain.

/// De-emphasized values (a low chance of rain); the value is also spoken.
private let dim = Palette.color(hex: 0x5A5A56)
private let axis = Palette.color(hex: 0x767672)
private let softRule = Palette.color(hex: 0x161615)

/// Mono label row: "NEXT HOUR ........ LIGHT RAIN 15:30 TO 16:10".
private struct ObsidianLabelRow: View {
    @Environment(\.lookTokens) private var t
    let title: String
    var detail: String?
    var detailColor: Color?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .lookLabel(t, size: 10, color: t.ink3, tracking: 1.6)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .lookLabel(t, size: 10, color: detailColor ?? t.ink3, tracking: 1.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

struct ObsidianHero: View {
    @Environment(\.lookTokens) private var t
    let context: ForecastContext

    var body: some View {
        let current = context.current
        let window = context.window
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        if context.location.isCurrentLocation {
                            Image(systemName: "location.fill")
                                .font(.system(size: 8, weight: .semibold))
                                .accessibilityHidden(true)
                        }
                        Text(context.location.name)
                            .lookLabel(t, size: 11, color: t.ink2, tracking: 2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    if context.location.isCurrentLocation {
                        Text("My Location")
                            .lookLabel(t, size: 10, color: t.ink3, tracking: 1.6)
                    }
                }
                .foregroundStyle(t.ink2)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("\(weekday) \(context.clock(context.now))")
                    .lookLabel(t, size: 11, color: t.ink2, tracking: 2)
                    .lineLimit(1)
            }

            HStack(alignment: .top, spacing: 6) {
                Text(context.degrees(current.temperature))
                    .font(t.font(.display, 148, relativeTo: .largeTitle))
                    .tracking(-8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .cssLineHeight(0.9, size: 148, face: t.display)
                Text("°")
                    .font(t.font(.display, 54, relativeTo: .largeTitle))
                    .foregroundStyle(t.rain)
                    .cssLineHeight(1, size: 54, face: t.display)
                    .padding(.top, 6)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.top, 18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Temperature \(context.formatter.temperature(current.temperature, includeUnit: true))")

            Text(sentenceCase(current.condition.description) + ".")
                .font(t.font(.headline, 22))
                .tracking(-0.3)
                .padding(.top, 14)
            Text(window.sentence(clock: context.shortClock) ?? "No rain in the next hour.")
                .font(t.font(.headline, 22))
                .tracking(-0.3)
                .foregroundStyle(window.isPrecipitating ? t.rain : t.ink3)
                .fixedSize(horizontal: false, vertical: true)
            if let comparison = context.yesterdayComparison {
                Text(comparison)
                    .font(t.font(.text, 15))
                    .foregroundStyle(t.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            HStack(spacing: 0) {
                stat("Feels", current.apparentTemperature, leading: false)
                if let today = context.today {
                    stat("High", today.high, leading: true)
                    stat("Low", today.low, leading: true)
                }
            }
            .overlay(alignment: .top) { Rectangle().fill(t.line).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(t.line).frame(height: 1) }
            .padding(.top, 22)
        }
        .padding(.top, 6)
    }

    private var weekday: String {
        context.formatter.weekdayShort(context.now, timeZone: context.timeZone).uppercased()
    }

    private func stat(_ label: String, _ celsius: Double, leading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .lookLabel(t, size: 10, color: t.ink3, tracking: 1.6)
            Text(context.temperature(celsius))
                .font(t.font(.number, 17))
                .foregroundStyle(t.ink)
        }
        .padding(.vertical, 12)
        .padding(.leading, leading ? 14 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            if leading { Rectangle().fill(t.line).frame(width: 1) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(context.spokenTemperature(celsius))")
    }
}

/// "Partly Cloudy" becomes "Partly cloudy".
func sentenceCase(_ text: String) -> String {
    text.prefix(1).uppercased() + text.dropFirst().lowercased()
}

struct ObsidianNextHour: View {
    @Environment(\.lookTokens) private var t
    let context: ForecastContext

    var body: some View {
        let window = context.window
        VStack(alignment: .leading, spacing: 0) {
            ObsidianLabelRow(
                title: "Next Hour",
                detail: window.obsidianHeader(clock: context.clock),
                detailColor: window.isPrecipitating ? t.rain : t.ink3
            )
            if let forecast = context.snapshot.nextHour, window.state != .unavailable {
                MinuteArea(points: MinuteChartData.points(for: forecast, now: context.now), color: t.rain)
                    .frame(height: 72)
                    .padding(.top, 10)
                HStack {
                    ForEach(["Now", "+15", "+30", "+45", "+60"], id: \.self) { label in
                        Text(label)
                        if label != "+60" { Spacer(minLength: 0) }
                    }
                }
                .lookLabel(t, size: 10, color: axis, tracking: 0)
                .padding(.top, 6)
                if context.nextHourResolution != nil || context.precipitationRateLine != nil {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let rate = context.precipitationRateLine {
                            Text(rate)
                                .font(t.font(.text, 14))
                                .foregroundStyle(t.rain)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if let resolution = context.nextHourResolution {
                            Text(resolution)
                                .lookLabel(t, size: 10, color: t.ink3, tracking: 1.6)
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(context.nextHourSpoken)
    }
}

/// The next hour as a thin line over a faint fill, with quarter-hour guides.
struct MinuteArea: View {
    let points: [MinuteChartPoint]
    let color: Color
    var guideColor: Color = Palette.color(hex: 0x161615)
    var fillOpacity: Double = 0.14

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let line = linePath(size)
            ZStack {
                Path { path in
                    for quarter in 1...3 {
                        let x = size.width * CGFloat(quarter) / 4
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    }
                }
                .stroke(guideColor, lineWidth: 1)
                areaPath(size, line: line).fill(color.opacity(fillOpacity))
                line.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }

    private func y(_ value: Double, height: CGFloat) -> CGFloat {
        height - CGFloat(min(max(value, 0), 1.1) / 1.1) * height
    }

    private func linePath(_ size: CGSize) -> Path {
        Path { path in
            for (index, point) in points.enumerated() {
                let location = CGPoint(x: CGFloat(point.minute / 60) * size.width, y: y(point.value, height: size.height))
                if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
            }
        }
    }

    private func areaPath(_ size: CGSize, line: Path) -> Path {
        var path = line
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }
}

struct ObsidianHourly: View {
    @Environment(\.lookTokens) private var t
    let context: ForecastContext

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ObsidianLabelRow(title: "Hourly", detail: "\(ForecastContext.hourlyLimit) hours")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(context.hourItems()) { item in
                        column(item)
                            .containerRelativeFrame(.horizontal, count: 6, spacing: 0)
                    }
                }
            }
            .overlay(alignment: .top) { Rectangle().fill(t.line).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(t.line).frame(height: 1) }
        }
    }

    @ViewBuilder
    private func column(_ item: ForecastHourItem) -> some View {
        switch item {
        case .hour(let hour):
            let chance = hour.precipitationChance ?? 0
            let now = context.isNow(hour)
            VStack(alignment: .leading, spacing: 6) {
                Text(now ? "Now" : context.hourLabel(hour.date))
                    .lookLabel(t, size: 10, color: t.ink2, tracking: 0)
                OutlineConditionIcon(hour.condition, isDaylight: hour.isDaylight)
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(t.ink2)
                    .frame(height: 16)
                Text(context.temperature(hour.temperature))
                    .font(t.font(.numberLight, 20))
                Text("\(Int((chance * 100).rounded()))%")
                    .lookLabel(t, size: 10, color: chance >= 0.2 ? t.rain : dim, tracking: 0)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(now ? "Now" : context.formatter.hour(hour.date, timeZone: context.timeZone)): \(context.spokenTemperature(hour.temperature)), \(hour.condition.description), \(context.formatter.percent(chance)) chance of precipitation")
        case .sun(let date, let rising):
            VStack(alignment: .leading, spacing: 6) {
                Text(context.clock(date))
                    .lookLabel(t, size: 10, color: t.ink2, tracking: 0)
                Image(systemName: rising ? "sunrise" : "sunset")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(t.ink2)
                    .frame(height: 16)
                Text(context.temperature(context.temperature(at: date)))
                    .font(t.font(.numberLight, 20))
                Text(rising ? "Rise" : "Set")
                    .lookLabel(t, size: 10, color: t.ink3, tracking: 0)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(rising ? "Sunrise" : "Sunset") at \(context.formatter.time(date, timeZone: context.timeZone)), \(context.spokenTemperature(context.temperature(at: date)))")
        }
    }
}

struct ObsidianDaily: View {
    @Environment(\.lookTokens) private var t
    let context: ForecastContext

    var body: some View {
        let days = context.days()
        let rangeLow = days.map(\.low).min() ?? 0
        let rangeHigh = days.map(\.high).max() ?? 1
        VStack(alignment: .leading, spacing: 4) {
            ObsidianLabelRow(title: "\(days.count) Days")
            Text(context.weekSummary)
                .font(t.font(.text, 15))
                .foregroundStyle(t.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    Button {
                        context.onSelectDay(day)
                    } label: {
                        row(day, rangeLow: rangeLow, rangeHigh: rangeHigh)
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(softRule).frame(height: 1)
                }
                Button(action: context.onTimeMachine) {
                    CardLinkRow(title: "Time Machine", systemImage: "clock.arrow.circlepath", detail: "Any date since 1940")
                        .padding(.top, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(_ day: DailyForecast, rangeLow: Double, rangeHigh: Double) -> some View {
        let label = context.formatter.dayLabel(day.date, timeZone: context.timeZone, now: context.now)
        let chance = day.precipitationChance ?? 0
        let today = context.isToday(day)
        return HStack(spacing: 12) {
            Text(label)
                .font(t.font(.text, 15))
                .frame(width: 76, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            OutlineConditionIcon(day.condition)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(t.ink2)
                .frame(width: 18)
            Text("\(Int((chance * 100).rounded()))%")
                .font(t.font(.number, 11))
                .foregroundStyle(chance >= 0.2 ? t.rain : dim)
                .frame(width: 30, alignment: .leading)
            Text(context.degrees(day.low))
                .font(t.font(.number, 13))
                .foregroundStyle(t.ink2)
                .frame(width: 26, alignment: .trailing)
            LookRangeBar(
                low: day.low, high: day.high, rangeLow: rangeLow, rangeHigh: rangeHigh,
                current: today ? context.current.temperature : nil,
                height: 3, fill: t.ink, track: t.track, marker: .tick(t.rain), rounded: false
            )
            Text(context.degrees(day.high))
                .font(t.font(.number, 13))
                .frame(width: 26, alignment: .trailing)
        }
        .frame(minHeight: 40)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(day.condition.description), high \(context.spokenTemperature(day.high)), low \(context.spokenTemperature(day.low)), \(context.formatter.percent(chance)) chance of precipitation")
    }
}
