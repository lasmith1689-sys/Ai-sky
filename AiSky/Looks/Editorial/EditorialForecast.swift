import AiSkyKit
import SwiftUI

// Editorial: a newspaper weather column on warm paper. A serif headline sentence leads, the
// temperature is set big in Newsreader, rows read like a table and blue marks rain.

/// Small caps section label over a 1 pt ink rule.
private struct EditorialLabel: View {
    @Environment(\.lookTokens) private var t
    let title: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .lookLabel(t, color: t.ink2)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let note {
                    Text(note)
                        .font(t.font(.emphasis, 14))
                        .foregroundStyle(t.rain)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            LookRule(strong: true)
        }
    }
}

struct EditorialHero: View {
    @Environment(\.lookTokens) private var t
    let context: ForecastContext

    var body: some View {
        let current = context.current
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 10) {
                // One line when it fits; the dateline drops under the place at large text sizes.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        placeName
                        Spacer(minLength: 8)
                        Text(dateline)
                            .lookLabel(t, color: t.ink2)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        placeName
                        Text(dateline)
                            .lookLabel(t, color: t.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                LookRule(strong: true)
            }

            Text(headline)
                .font(t.font(.headline, 33, relativeTo: .title))
                .tracking(-0.6)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)

            HStack(alignment: .top, spacing: 18) {
                Text(context.temperature(current.temperature))
                    .font(t.font(.display, 118, relativeTo: .largeTitle))
                    .tracking(-5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .cssLineHeight(0.86, size: 118, face: t.display)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityLabel("Temperature \(context.formatter.temperature(current.temperature, includeUnit: true))")
                VStack(alignment: .leading, spacing: 5) {
                    Text(sentenceCase(current.condition.description))
                        .font(t.font(.textStrong, 13))
                        .foregroundStyle(t.ink)
                    ForEach(details, id: \.self) { line in
                        Text(line)
                    }
                    .font(t.font(.text, 13))
                    .foregroundStyle(t.ink2)
                }
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 18)
            .padding(.bottom, 18)
            LookRule()
        }
        .padding(.top, 6)
    }

    private var placeName: some View {
        Text(context.location.name)
            .lookLabel(t, color: t.ink2)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityAddTraits(.isHeader)
    }

    /// "Tuesday 29 September · 3:12 PM".
    private var dateline: String {
        let day = LookClock.twentyFourHour(context.now, timeZone: context.timeZone, pattern: "EEEE d MMMM")
        return "\(day) · \(context.formatter.time(context.now, timeZone: context.timeZone))"
    }

    private var headline: String {
        let fallback = ForecastNarrator.daySummary(hours: context.snapshot.hourly, now: context.now, timeZone: context.timeZone, formatter: context.formatter)
        return EditorialHeadline.sentence(window: context.window, timeZone: context.timeZone, fallback: fallback)
    }

    private var details: [String] {
        let formatter = context.formatter
        let current = context.current
        var lines = ["Feels like \(formatter.temperature(current.apparentTemperature))"]
        if let today = context.today {
            lines.append("High \(formatter.temperature(today.high)), low \(formatter.temperature(today.low))")
        }
        if let speed = current.windSpeed {
            if speed < 1 {
                lines.append("Calm")
            } else if let direction = current.windDirection {
                lines.append("\(WeatherFormatter.compassDirectionName(direction).capitalized) wind, \(formatter.windSpeed(speed))")
            } else {
                lines.append("Wind \(formatter.windSpeed(speed))")
            }
        }
        return lines
    }
}

struct EditorialNextHour: View {
    @Environment(\.lookTokens) private var t
    let context: ForecastContext

    var body: some View {
        let window = context.window
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("The Next Hour")
                    .lookLabel(t, color: t.ink2)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(window.editorialNote(clock: context.shortClock))
                    .font(t.font(.emphasis, 14))
                    .foregroundStyle(window.isPrecipitating ? t.rain : t.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if let forecast = context.snapshot.nextHour, window.state != .unavailable {
                MinuteBars(forecast: forecast, now: context.now, spacing: 4, wetColor: t.rain, dryColor: .clear, dryHeight: 0, cornerRadius: 0)
                    .frame(height: 44)
                    .padding(.top, 10)
                LookRule(strong: true)
                HStack {
                    ForEach(0..<5) { index in
                        Text(context.shortClock(context.now.addingTimeInterval(Double(index) * 15 * 60)))
                        if index < 4 { Spacer(minLength: 0) }
                    }
                }
                .font(t.font(.number, 12))
                .foregroundStyle(t.ink2)
                .padding(.top, 6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("The next hour. \(NextHourSummarizer.summarize(context.snapshot.nextHour, now: context.now).text)")
    }
}

/// The coming hours as a table: time, conditions, chance and temperature.
struct EditorialHourly: View {
    @Environment(\.lookTokens) private var t
    let context: ForecastContext
    @State private var showsAll = false

    private struct Row: Identifiable {
        let id: String
        let date: Date
        let time: String
        let words: String
        let chance: Double?
        let temperature: Double
        let isSun: Bool
    }

    var body: some View {
        let rows = self.rows
        let visible = showsAll ? rows : Array(rows.prefix(8))
        VStack(alignment: .leading, spacing: 0) {
            EditorialLabel(title: periodTitle)
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                if index > 0 { LookRule() }
                rowView(row)
            }
            if rows.count > 8 {
                LookRule()
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { showsAll.toggle() }
                } label: {
                    HStack {
                        Text(showsAll ? "Fewer hours" : "The next 24 hours")
                            .lookLabel(t, color: t.accent)
                        Spacer()
                        Image(systemName: showsAll ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(t.accent)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// "This evening", "Tonight"... for the current local hour.
    private var periodTitle: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = context.timeZone
        switch calendar.component(.hour, from: context.now) {
        case 5..<12: return "This Morning"
        case 12..<17: return "This Afternoon"
        case 17..<21: return "This Evening"
        default: return "Tonight"
        }
    }

    private var rows: [Row] {
        let hours = Array(context.hours(25).dropFirst())
        guard let first = hours.first?.date, let last = hours.last?.date else { return [] }
        var rows = hours.map { hour in
            Row(id: "h\(hour.date.timeIntervalSince1970)", date: hour.date,
                time: context.formatter.hour(hour.date, timeZone: context.timeZone),
                words: sentenceCase(hour.condition.description), chance: hour.precipitationChance,
                temperature: hour.temperature, isSun: false)
        }
        for event in context.sunEvents(from: first, to: last) {
            rows.append(Row(id: "s\(event.date.timeIntervalSince1970)", date: event.date,
                            time: context.shortClock(event.date), words: event.rising ? "Sunrise" : "Sunset",
                            chance: nil, temperature: context.snapshot.conditions(at: event.date).temperature, isSun: true))
        }
        return rows.sorted { $0.date < $1.date }
    }

    private func rowView(_ row: Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(row.time)
                .font(t.font(.textStrong, 14))
                .frame(width: 70, alignment: .leading)
            Text(row.words)
                .font(t.font(.text, 14))
                .foregroundStyle(t.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(chanceText(row.chance))
                .font(t.font(.emphasis, 14))
                .foregroundStyle(t.rain)
                .frame(width: 52, alignment: .trailing)
            Text(context.temperature(row.temperature))
                .font(t.font(.number, 19))
                .frame(width: 50, alignment: .trailing)
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
    }

    private func chanceText(_ chance: Double?) -> String {
        guard let chance, chance >= 0.15 else { return "" }
        return "\(Int((chance * 100).rounded()))%"
    }
}

struct EditorialDaily: View {
    @Environment(\.lookTokens) private var t
    let context: ForecastContext

    var body: some View {
        let days = context.days()
        VStack(alignment: .leading, spacing: 0) {
            EditorialLabel(title: "The Week Ahead")
            Text(ForecastNarrator.weekSummary(days: days, now: context.now, timeZone: context.timeZone, formatter: context.formatter))
                .font(t.font(.number, 17))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 10)
            ForEach(days) { day in
                LookRule()
                Button {
                    context.onSelectDay(day)
                } label: {
                    row(day)
                }
                .buttonStyle(.plain)
            }
            LookRule()
            Button(action: context.onTimeMachine) {
                CardLinkRow(title: "Time Machine", systemImage: "clock.arrow.circlepath", detail: "Any date since 1940")
                    .padding(.top, 6)
            }
            .buttonStyle(.plain)
        }
    }

    private func row(_ day: DailyForecast) -> some View {
        let label = context.formatter.dayLabel(day.date, timeZone: context.timeZone, now: context.now)
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(label)
                .font(t.font(.textStrong, 14))
                .frame(width: 88, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(sentenceCase(day.condition.description))
                .font(t.font(.text, 14))
                .foregroundStyle(t.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(chanceText(day.precipitationChance))
                .font(t.font(.emphasis, 14))
                .foregroundStyle(t.rain)
                .frame(width: 44, alignment: .trailing)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(context.temperature(day.high))
                    .font(t.font(.number, 19))
                Text(context.temperature(day.low))
                    .font(t.font(.number, 16))
                    .foregroundStyle(t.ink2)
            }
            .frame(width: 84, alignment: .trailing)
        }
        .frame(minHeight: 38)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(day.condition.description), high \(context.temperature(day.high)), low \(context.temperature(day.low))")
    }

    private func chanceText(_ chance: Double?) -> String {
        guard let chance, chance >= 0.15 else { return "" }
        return "\(Int((chance * 100).rounded()))%"
    }
}
