import AiSkyKit
import Charts
import SwiftUI

/// Precip-style rainfall accounting: what fell recently, what's coming, and a daily history chart.
struct PrecipitationCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lookTokens) private var lookTokens
    let snapshot: WeatherSnapshot
    let now: Date
    var onShowHistory: (() -> Void)?

    var body: some View {
        let formatter = model.formatter
        let totals = PrecipitationTotals.compute(for: snapshot, now: now)
        let t = lookTokens.toned(.cobalt)
        WeatherCard(title: "Precipitation", systemImage: "drop.fill", accessory: lastRainText(totals), tone: .cobalt) {
            HStack(alignment: .top) {
                bigStat(title: "Past 24 hrs", value: totals.past24Hours, formatter: formatter, t: t)
                Spacer()
                bigStat(title: "Next 24 hrs", value: totals.next24Hours, formatter: formatter, t: t, alignment: .trailing)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                smallStat("Past hour", totals.pastHour, formatter, t)
                smallStat("Today so far", totals.todaySoFar, formatter, t)
                smallStat("Next hour", totals.nextHour, formatter, t)
                smallStat("Past 7 days", totals.past7Days, formatter, t)
                smallStat("Past 30 days", totals.past30Days, formatter, t)
                smallStat("Next 7 days", totals.next7Days, formatter, t)
            }

            if let snow = totals.snowPast24Hours, snow >= 0.1 {
                Label("\(formatter.snowfall(snow)) of snow in the past 24 hours", systemImage: "snowflake")
                    .font(t.font(.text, t.bodySize - 2))
            }
            if let snow = totals.snowNext24Hours, snow >= 0.1 {
                Label("\(formatter.snowfall(snow)) of snow expected in the next 24 hours", systemImage: "snowflake")
                    .font(t.font(.text, t.bodySize - 2))
            }

            if !totals.dailyBars.isEmpty {
                PrecipitationHistoryChart(bars: totals.dailyBars, formatter: formatter, timeZone: snapshot.timeZone)
                    .frame(height: 130)
                    .padding(.top, 4)
                HStack(spacing: 14) {
                    legend(color: t.rain, text: "Observed")
                    legend(color: t.rain.opacity(0.4), text: "Forecast")
                }
                .font(t.look == .liquid ? .caption2 : t.font(.label, 10))
                .foregroundStyle(t.ink2)
            }

            if let onShowHistory {
                if t.surfaceStyle != .block { LookRule() }
                Button(action: onShowHistory) {
                    CardLinkRow(title: "Rainfall History", systemImage: "chart.bar.xaxis", detail: "Any dates · vs. normal")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func bigStat(title: String, value: Double?, formatter: WeatherFormatter, t: LookTokens, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(t.look == .liquid ? .caption : t.font(.text, 12))
                .foregroundStyle(t.ink2)
            Text(value.map { formatter.precipitation($0) } ?? "--")
                .font(t.look == .liquid ? .title2.weight(.semibold) : t.font(t.look == .chroma ? .headline : .numberLight, 26))
        }
    }

    private func smallStat(_ title: String, _ value: Double?, _ formatter: WeatherFormatter, _ t: LookTokens) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(t.look == .liquid ? .caption2 : t.font(.text, 11))
                .foregroundStyle(t.ink2)
            Text(value.map { formatter.precipitation($0) } ?? "--")
                .font(t.look == .liquid ? .callout.weight(.medium) : t.font(.number, 15))
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 8)
            Text(text)
        }
    }

    private func lastRainText(_ totals: PrecipitationTotals) -> String? {
        guard let last = totals.lastPrecipitation else { return nil }
        let hours = now.timeIntervalSince(last.date) / 3600
        if hours < 1 { return "Raining recently" }
        if hours < 48 { return "Last rain \(Int(hours)) hr ago" }
        return "Last rain \(Int(hours / 24)) days ago"
    }
}

/// Daily totals: past two weeks (solid), today and the week ahead (lighter = forecast).
struct PrecipitationHistoryChart: View {
    @Environment(\.lookTokens) private var t
    let bars: [PrecipitationTotals.Bar]
    let formatter: WeatherFormatter
    let timeZone: TimeZone

    var body: some View {
        Chart {
            ForEach(bars) { bar in
                BarMark(
                    x: .value("Day", label(bar)),
                    y: .value("Observed", formatter.precipitationValue(bar.observed)),
                    width: .ratio(0.7)
                )
                .foregroundStyle(t.rain)
                BarMark(
                    x: .value("Day", label(bar)),
                    y: .value("Forecast", formatter.precipitationValue(bar.forecast)),
                    width: .ratio(0.7)
                )
                .foregroundStyle(t.rain.opacity(0.4))
            }
            if let today = bars.first(where: \.isToday) {
                RuleMark(x: .value("Day", label(today)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .foregroundStyle(t.ink2)
                    .annotation(position: .top, alignment: .center) {
                        Text("Today")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(t.ink)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: axisLabels) { value in
                // Edge labels grow inward so they aren't clipped to "…".
                AxisValueLabel(anchor: labelAnchor(value.as(String.self))) {
                    if let text = value.as(String.self) {
                        Text(text)
                            .font(axisFont)
                            .foregroundStyle(t.ink2)
                    }
                }
            }
        }
        .chartYScale(domain: 0...yMaximum)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(t.grid)
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(String(format: formatter.units.precipitation == .inches ? "%.1f" : "%.0f", amount))
                            .font(axisFont)
                            .foregroundStyle(t.ink2)
                    }
                }
            }
        }
    }

    private var axisFont: Font {
        t.look == .liquid ? .caption2 : t.font(.label, 10, relativeTo: .caption2)
    }

    /// Unique per day within the three-week window, e.g. "Sep 28".
    private func label(_ bar: PrecipitationTotals.Bar) -> String {
        formatter.monthDay(bar.date, timeZone: timeZone)
    }

    private var axisLabels: [String] {
        guard let first = bars.first, let last = bars.last else { return [] }
        var labels = [label(first)]
        if let today = bars.first(where: \.isToday) { labels.append(label(today)) }
        labels.append(label(last))
        return labels
    }

    private func labelAnchor(_ text: String?) -> UnitPoint {
        if text == axisLabels.first { return .topLeading }
        if text == axisLabels.last { return .topTrailing }
        return .top
    }

    /// Room above the tallest bar, and never less than a light shower so dry weeks stay flat.
    private var yMaximum: Double {
        let tallest = bars.map { formatter.precipitationValue($0.total) }.max() ?? 0
        let minimum = formatter.units.precipitation == .inches ? 0.25 : 5
        return max(tallest * 1.15, minimum)
    }
}
