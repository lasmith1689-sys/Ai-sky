import AiSkyKit
import SwiftUI

// Horizon: deep navy, Manrope, and the day as a vertical ribbon: condition color bands, the
// temperature as a curve of points, a dashed sunset marker and the chance of rain per hour.

private let dimLabel = Palette.color(hex: 0x5D6A80)
private let rainWords = Palette.color(hex: 0x9FC9FF)

struct HorizonHero: View {
    @Environment(\.lookTokens) private var t
    let context: ForecastContext

    var body: some View {
        let current = context.current
        let window = context.window
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    if context.location.isCurrentLocation {
                        Image(systemName: "location.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .accessibilityLabel("Current location")
                    }
                    Text(context.location.name)
                        .font(t.font(.headline, 20))
                        .tracking(-0.2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(context.formatter.time(context.now, timeZone: context.timeZone))
                    .font(t.font(.text, 13))
                    .foregroundStyle(t.ink2)
            }
            HStack(alignment: .center, spacing: 18) {
                Text(context.temperature(current.temperature))
                    .font(t.font(.display, 92, relativeTo: .largeTitle))
                    .tracking(-4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .cssLineHeight(1, size: 92, face: t.display)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityLabel("Temperature \(context.formatter.temperature(current.temperature, includeUnit: true))")
                VStack(alignment: .leading, spacing: 3) {
                    Text(sentenceCase(current.condition.description))
                        .font(t.font(.headline, 16))
                    Text(window.status() ?? "Dry for the next hour")
                        .font(t.font(.textStrong, 14))
                        .foregroundStyle(window.isPrecipitating ? t.accent : t.ink2)
                    Text(rangeLine)
                        .font(t.font(.text, 14))
                        .foregroundStyle(t.ink2)
                }
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 6)
    }

    private var rangeLine: String {
        var text = "Feels \(context.temperature(context.current.apparentTemperature))"
        if let today = context.today {
            text += " · H \(context.temperature(today.high)) L \(context.temperature(today.low))"
        }
        return text
    }
}

/// Horizon shows the next hour below the timeline (see ``HorizonDaily``); the hero already says
/// when rain starts.
struct HorizonNextHour: View {
    let context: ForecastContext

    var body: some View {
        EmptyView()
    }
}

/// The next twelve hours as a vertical ribbon.
struct HorizonTimeline: View {
    @Environment(\.lookTokens) private var t
    let context: ForecastContext

    private let rowHeight: CGFloat = 62

    var body: some View {
        let hours = context.hours(12)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Next \(hours.count) Hours")
                Spacer(minLength: 8)
                Text("Scroll for tomorrow")
            }
            .lookLabel(t, size: 11, color: dimLabel, tracking: 1.6)
            .accessibilityHidden(true)

            GeometryReader { proxy in
                timeline(hours: hours, width: proxy.size.width)
            }
            .frame(height: rowHeight * CGFloat(hours.count))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenSummary(hours))
        }
        .padding(.top, 8)
    }

    private func timeline(hours: [HourlyForecast], width: CGFloat) -> some View {
        let temps = hours.map { context.formatter.temperatureValue($0.temperature) }
        let low = temps.min() ?? 0
        let high = temps.max() ?? 1
        let span = max(high - low, 1)
        let minX = width * 200 / 350
        let maxX = width * 330 / 350
        let points: [CGPoint] = temps.enumerated().map { index, value in
            CGPoint(x: minX + CGFloat((value - low) / span) * (maxX - minX), y: rowHeight / 2 + rowHeight * CGFloat(index))
        }
        let start = hours.first?.date ?? context.now
        let sunEvents = context.sunEvents(from: start, to: start.addingTimeInterval(Double(max(hours.count - 1, 0)) * 3600))
        let conditionWidth = min(104, width * 0.3)
        return ZStack(alignment: .topLeading) {
            ribbon(hours)
            sunMarkers(sunEvents, start: start, width: width)
            curveLayer(points: points, hours: hours, labelsRightOf: 88 + conditionWidth + 4)
            timesColumn(hours)
            conditionsColumn(hours, width: conditionWidth)
        }
        .frame(width: width, height: rowHeight * CGFloat(hours.count), alignment: .topLeading)
    }

    /// Condition color bands.
    private func ribbon(_ hours: [HourlyForecast]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                Rectangle()
                    .fill(ribbonColor(hour, index: index, hours: hours))
                    .frame(height: rowHeight)
            }
        }
        .frame(width: 12)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .offset(x: 62)
    }

    /// Dashed sunrise and sunset lines across the ribbon.
    private func sunMarkers(_ events: [(date: Date, rising: Bool)], start: Date, width: CGFloat) -> some View {
        ForEach(Array(events.enumerated()), id: \.offset) { _, event in
            let y = rowHeight / 2 + rowHeight * CGFloat(event.date.timeIntervalSince(start) / 3600)
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 80, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
                .stroke(t.sun.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                Text("\(event.rising ? "Sunrise" : "Sunset") \(context.shortClock(event.date))")
                    .lookLabel(t, size: 11, color: t.sun, tracking: 1)
                    .fixedSize()
                    .frame(width: width, alignment: .trailing)
                    .offset(y: y - 18)
            }
        }
    }

    /// The temperature curve, its points and their labels. A label sits left of its point unless
    /// that would run into a condition name, then it moves to the right.
    private func curveLayer(points: [CGPoint], hours: [HourlyForecast], labelsRightOf limit: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            curve(points).stroke(t.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                let named = index == 0 || hours[index - 1].condition.family != hours[index].condition.family
                let onRight = named && point.x - 56 < limit
                pointMark(first: index == 0).position(point)
                Text(context.temperature(hours[index].temperature))
                    .font(t.font(index == 0 ? .textStrong : .textMedium, index == 0 ? 17 : 16))
                    .fixedSize()
                    .frame(width: 60, alignment: onRight ? .leading : .trailing)
                    .position(x: onRight ? point.x + 46 : point.x - 46, y: point.y)
            }
        }
    }

    @ViewBuilder
    private func pointMark(first: Bool) -> some View {
        if first {
            Circle().fill(t.background)
                .overlay(Circle().stroke(t.ink, lineWidth: 2))
                .overlay(Circle().fill(t.ink).frame(width: 6, height: 6))
                .frame(width: 14, height: 14)
        } else {
            Circle().fill(t.ink).frame(width: 7, height: 7)
        }
    }

    /// Hour labels with the chance of precipitation under them.
    private func timesColumn(_ hours: [HourlyForecast]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                let chance = hour.precipitationChance ?? 0
                VStack(alignment: .trailing, spacing: 0) {
                    Text(index == 0 ? "Now" : context.formatter.hour(hour.date, timeZone: context.timeZone))
                        .font(t.font(index == 0 ? .label : .textStrong, 14))
                        .foregroundStyle(index >= 6 ? t.ink2 : t.ink)
                    if chance >= 0.2 {
                        Text(context.formatter.chance(chance))
                            .font(t.font(.label, 11))
                            .foregroundStyle(t.accent)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 50, height: rowHeight, alignment: .trailing)
            }
        }
    }

    /// Conditions, written only when they change.
    private func conditionsColumn(_ hours: [HourlyForecast], width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                let changed = index == 0 || hours[index - 1].condition.family != hour.condition.family
                Text(changed ? sentenceCase(hour.condition.description) : " ")
                    .font(t.font(.textStrong, 12))
                    .foregroundStyle(hour.condition.isPrecipitation ? rainWords : t.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: width, height: rowHeight, alignment: .leading)
            }
        }
        .offset(x: 88)
    }

    /// Smooth vertical curve through the hourly points.
    private func curve(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for index in points.indices.dropFirst() {
                let a = points[index - 1]
                let b = points[index]
                let bend = (b.y - a.y) * 0.44
                path.addCurve(to: b, control1: CGPoint(x: a.x, y: a.y + bend), control2: CGPoint(x: b.x, y: b.y - bend))
            }
        }
    }

    /// Condition colors by day; deepening blues after sunset.
    private func ribbonColor(_ hour: HourlyForecast, index: Int, hours: [HourlyForecast]) -> Color {
        let day: UInt32
        switch hour.condition.family {
        case .clear: day = 0xC9D8EC
        case .partlyCloudy: day = 0xAAB8CC
        case .cloudy: day = 0x9AA6B4
        case .fog: day = 0xA7A39A
        case .windy: day = 0x9FC5C1
        case .lightRain: day = 0x7FB8FF
        case .rain: day = 0x4F8FF7
        case .heavyRain: day = 0x2F5BEA
        case .sleet: day = 0x9AA8FF
        case .snow: day = 0xDCE6FF
        case .storm: day = 0x7B5CF0
        }
        guard !hour.isDaylight else { return Palette.color(hex: day) }
        switch hour.condition.family {
        case .clear:
            // Clear nights deepen hour by hour after dusk.
            let shades: [UInt32] = [0x4A4F7E, 0x2E3C78, 0x243063, 0x1B2552]
            return Palette.color(hex: shades[min(nightHoursBefore(index, in: hours), shades.count - 1)])
        case .partlyCloudy: return Palette.color(hex: 0x4A4F7E)
        case .cloudy, .windy: return Palette.color(hex: 0x4B5570)
        case .fog: return Palette.color(hex: 0x55586A)
        default: return Palette.color(hex: day).opacity(0.72)
        }
    }

    private func nightHoursBefore(_ index: Int, in hours: [HourlyForecast]) -> Int {
        var count = 0
        var i = index - 1
        while i >= 0, !hours[i].isDaylight {
            count += 1
            i -= 1
        }
        return count
    }

    private func spokenSummary(_ hours: [HourlyForecast]) -> String {
        let parts = hours.prefix(12).enumerated().map { index, hour -> String in
            let time = index == 0 ? "Now" : context.formatter.hour(hour.date, timeZone: context.timeZone)
            var text = "\(time) \(context.temperature(hour.temperature)), \(hour.condition.description)"
            if let chance = hour.precipitationChance, chance >= 0.2 {
                text += ", \(context.formatter.chance(chance)) chance"
            }
            return text
        }
        return "Next \(hours.count) hours. " + parts.joined(separator: ". ")
    }
}

/// The next hour and the week, below the timeline.
struct HorizonDaily: View {
    @Environment(\.lookTokens) private var t
    let context: ForecastContext

    var body: some View {
        let days = context.days()
        let rangeLow = days.map(\.low).min() ?? 0
        let rangeHigh = days.map(\.high).max() ?? 1
        VStack(spacing: t.sectionSpacing) {
            HorizonMinuteCard(context: context)
            WeatherCard(title: "The Week") {
                VStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        if index > 0 { LookRule() }
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
            }
        }
    }

    private func row(_ day: DailyForecast, rangeLow: Double, rangeHigh: Double) -> some View {
        let label = context.formatter.dayLabel(day.date, timeZone: context.timeZone, now: context.now)
        let today = context.isToday(day)
        return HStack(spacing: 10) {
            Text(label)
                .font(t.font(.textStrong, 15))
                .frame(width: 84, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            OutlineConditionIcon(day.condition)
                .font(.system(size: 16))
                .foregroundStyle(Palette.color(hex: 0xAAB8CC))
                .frame(width: 24)
            Text(chanceText(day))
                .font(t.font(.label, 11))
                .foregroundStyle(t.accent)
                .frame(width: 32, alignment: .leading)
            Text(context.degrees(day.low))
                .font(t.font(.textMedium, 15))
                .foregroundStyle(t.ink2)
                .frame(width: 26, alignment: .trailing)
            LookRangeBar(
                low: day.low, high: day.high, rangeLow: rangeLow, rangeHigh: rangeHigh,
                current: today ? context.current.temperature : nil,
                height: 5, fill: t.accent, track: t.track, marker: .dot(t.ink, ring: t.surface)
            )
            Text(context.degrees(day.high))
                .font(t.font(.textStrong, 15))
                .frame(width: 26, alignment: .trailing)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(day.condition.description), high \(context.temperature(day.high)), low \(context.temperature(day.low))")
    }

    private func chanceText(_ day: DailyForecast) -> String {
        guard let chance = day.precipitationChance, chance >= 0.15 else { return "" }
        return context.formatter.chance(chance)
    }
}

private struct HorizonMinuteCard: View {
    @Environment(\.lookTokens) private var t
    let context: ForecastContext

    var body: some View {
        let window = context.window
        let summary = NextHourSummarizer.summarize(context.snapshot.nextHour, now: context.now)
        WeatherCard(title: "Next Hour", accessory: context.snapshot.nextHour?.isMinuteByMinute == true ? "Minute by minute" : "15-minute data") {
            Text(summary.text)
                .font(t.font(.textStrong, 15))
                .foregroundStyle(window.isPrecipitating ? t.ink : t.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if let forecast = context.snapshot.nextHour, window.state != .unavailable {
                MinuteArea(points: MinuteChartData.points(for: forecast, now: context.now), color: t.accent, guideColor: t.line, fillOpacity: 0.2)
                    .frame(height: 56)
                HStack {
                    ForEach(["Now", "15", "30", "45", "60"], id: \.self) { label in
                        Text(label)
                        if label != "60" { Spacer(minLength: 0) }
                    }
                }
                .font(t.font(.label, 11))
                .foregroundStyle(t.ink3)
            }
        }
    }
}
