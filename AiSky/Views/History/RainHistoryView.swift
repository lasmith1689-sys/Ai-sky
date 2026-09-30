import AiSkyKit
import Charts
import SwiftUI

/// Precip-style rainfall history: totals for any period back to 1940, compared with the
/// 1991–2020 normal and with the same days last year. Tap a day to open it in the Time Machine.
struct RainHistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lookTokens) private var t
    @State private var history: RainHistoryModel

    init(location: WeatherLocation, snapshot: WeatherSnapshot?) {
        _history = State(initialValue: RainHistoryModel(location: location, snapshot: snapshot))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LookPageBackground(condition: .rain, isDaylight: true)
                    .ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: t.sectionSpacing) {
                        LookChips(options: RainHistoryModel.Choice.allCases, selection: $history.choice, title: \.title)
                        if history.choice == .custom {
                            customRangePicker
                        }
                        content
                    }
                    .padding(.horizontal, t.gutter)
                    .padding(.vertical, 16)
                }
            }
            .lookSky(.rain, isDaylight: true)
            .foregroundStyle(t.ink)
            .lookNavigationTitle("Rainfall · \(history.location.name)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: Date.self) { date in
                TimeMachineView(location: history.location, timeZone: history.calendar.timeZone, date: date)
            }
        }
        .task {
            await history.load()
        }
        .onChange(of: history.choice) { _, _ in
            Task { await history.loadPeriodIfNeeded() }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var content: some View {
        if !history.hasData, let message = history.failureMessage {
            ErrorCard(message: message) {
                Task { await history.retry() }
            }
        } else if !history.hasData {
            ProgressView("Loading rainfall history…")
                .tint(t.ink2)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            let formatter = model.formatter
            let range = history.range
            let summary = history.record.summary(for: range)
            let chart = history.record.bars(for: range)
            TotalCard(summary: summary, formatter: formatter, calendar: history.calendar, normalsState: history.normalsState, isLoading: history.isLoading)
            WeatherCard(title: chartTitle(chart.0), systemImage: "chart.bar.fill", tone: .cobalt) {
                RainfallBarChart(bars: chart.1, granularity: chart.0, formatter: formatter, calendar: history.calendar)
                    .frame(height: 170)
                if history.record.normals != nil && chart.0 != .day {
                    legend
                }
            }
            if summary.dayCount >= 14 {
                WeatherCard(title: "Running Total", systemImage: "chart.line.uptrend.xyaxis", tone: .navy) {
                    CumulativeRainChart(points: history.record.cumulative(for: range), formatter: formatter, calendar: history.calendar)
                        .frame(height: 150)
                    if history.record.normals != nil {
                        legend
                    }
                }
            }
            RainStatsGrid(summary: summary, normals: history.record.normals, formatter: formatter, timeZone: history.calendar.timeZone)
            WetDaysCard(summary: summary, record: history.record, formatter: formatter)
            Text("Totals for the last three months come from Open-Meteo's weather-model analyses; older days come from ERA5 and ECMWF reanalysis. They're estimates for the area, not rain-gauge readings. Normals are the 1991–2020 average.")
                .font(t.look == .liquid ? .caption : t.font(.text, 12))
                .foregroundStyle(t.ink2)
        }
    }

    private var customRangePicker: some View {
        WeatherCard(title: "Dates", systemImage: "calendar") {
            DatePicker("From", selection: $history.customStart, in: history.earliestDate...history.today, displayedComponents: .date)
            DatePicker("To", selection: $history.customEnd, in: history.earliestDate...history.today, displayedComponents: .date)
            Text("Any dates since 1940, up to ten years at a time.")
                .font(t.look == .liquid ? .caption : t.font(.text, 12))
                .foregroundStyle(t.ink2)
        }
        .environment(\.timeZone, history.calendar.timeZone)
        .onChange(of: history.customStart) { _, _ in customRangeChanged() }
        .onChange(of: history.customEnd) { _, _ in customRangeChanged() }
    }

    private func customRangeChanged() {
        history.normalizeCustomRange()
        Task { await history.loadPeriodIfNeeded() }
    }

    private var legend: some View {
        RainLegend()
    }

    private func chartTitle(_ granularity: RainfallGranularity) -> String {
        switch granularity {
        case .day: return "Daily Totals"
        case .week: return "Weekly Totals"
        case .month: return "Monthly Totals"
        case .year: return "Yearly Totals"
        }
    }
}

// MARK: - Legend

/// "This period" bars against the dashed normal, inside a card that has set the tokens.
private struct RainLegend: View {
    @Environment(\.lookTokens) private var t

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(t.rain).frame(width: 10, height: 8)
                Text("This period")
            }
            HStack(spacing: 4) {
                Rectangle()
                    .fill(t.ink)
                    .frame(width: 12, height: 2)
                Text("Normal (1991–2020)")
            }
        }
        .font(t.look == .liquid ? .caption2 : t.font(.label, 10))
        .foregroundStyle(t.ink2)
    }
}

// MARK: - Total

private struct TotalCard: View {
    @Environment(\.lookTokens) private var t
    let summary: RainfallRecord.Summary
    let formatter: WeatherFormatter
    let calendar: Calendar
    let normalsState: RainHistoryModel.LoadState
    let isLoading: Bool

    var body: some View {
        WeatherCard(title: "Total", systemImage: "drop.fill", accessory: rangeText) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(formatter.precipitation(summary.total))
                    .font(t.look == .liquid ? .system(size: 44, weight: .semibold) : t.font(t.look == .chroma ? .headline : .numberLight, 44))
                    .contentTransition(.numericText())
                if isLoading {
                    ProgressView().tint(t.ink2)
                }
            }
            if summary.snowfall >= 0.1 {
                Label("Including \(formatter.snowfall(summary.snowfall)) of snow", systemImage: "snowflake")
                    .font(t.look == .liquid ? .subheadline : t.font(.text, t.bodySize))
            }
            if let normalText {
                Label(normalText, systemImage: normalSymbol)
                    .font(t.look == .liquid ? .subheadline.weight(.medium) : t.font(.textMedium, t.bodySize))
            } else if normalsState == .loading {
                Label("Comparing with 1991–2020 normals…", systemImage: "hourglass")
                    .font(t.look == .liquid ? .subheadline : t.font(.text, t.bodySize))
                    .foregroundStyle(t.ink2)
            }
            if let lastYear = summary.lastYear {
                Label("Same days last year: \(formatter.precipitation(lastYear))", systemImage: "calendar.badge.clock")
                    .font(t.look == .liquid ? .subheadline : t.font(.text, t.bodySize))
                    .foregroundStyle(t.ink2)
            }
            if summary.missingDays > 0 {
                Text(summary.missingDays == 1 ? "1 day isn't available yet." : "\(summary.missingDays) days aren't available yet.")
                    .font(t.look == .liquid ? .caption : t.font(.text, 12))
                    .foregroundStyle(t.ink2)
            }
        }
    }

    private var rangeText: String {
        let timeZone = calendar.timeZone
        let start = summary.range.lowerBound
        let end = summary.range.upperBound
        if calendar.isDate(start, inSameDayAs: end) {
            return formatter.mediumDate(start, timeZone: timeZone)
        }
        let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: end)
        let first = sameYear ? formatter.monthDay(start, timeZone: timeZone) : formatter.mediumDate(start, timeZone: timeZone)
        return "\(first) – \(formatter.mediumDate(end, timeZone: timeZone))"
    }

    private var normalText: String? {
        guard let normal = summary.normal, let departure = summary.departureFromNormal else { return nil }
        guard let fraction = summary.fractionOfNormal else {
            return "Normal for these days: \(formatter.precipitation(normal))"
        }
        let percent = Int((fraction * 100).rounded())
        if abs(fraction - 1) < 0.05 {
            return "About normal (\(formatter.precipitation(normal)))"
        }
        let direction = departure > 0 ? "above" : "below"
        return "\(formatter.precipitation(abs(departure))) \(direction) normal · \(percent)%"
    }

    private var normalSymbol: String {
        guard let fraction = summary.fractionOfNormal else { return "equal.circle" }
        if abs(fraction - 1) < 0.05 { return "equal.circle" }
        return fraction > 1 ? "arrow.up.circle" : "arrow.down.circle"
    }
}

// MARK: - Charts

/// Charts bin dates with the device's calendar, so each local day is re-expressed as the same
/// calendar day in the device's time zone.
private func chartDate(_ date: Date, calendar: Calendar) -> Date {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return Calendar.current.date(from: parts) ?? date
}

private struct RainfallBarChart: View {
    @Environment(\.lookTokens) private var t
    let bars: [RainfallRecord.Bar]
    let granularity: RainfallGranularity
    let formatter: WeatherFormatter
    let calendar: Calendar

    var body: some View {
        Chart {
            ForEach(bars) { bar in
                BarMark(
                    x: .value("Period", chartDate(bar.start, calendar: calendar), unit: unit),
                    y: .value("Precipitation", formatter.precipitationValue(bar.amount))
                )
                .foregroundStyle(t.rain.opacity(bar.isIncomplete ? 0.6 : 1))
                .cornerRadius(2)
            }
            if granularity != .day {
                ForEach(bars.filter { $0.normal != nil }) { bar in
                    RuleMark(
                        xStart: .value("Start", binStart(bar)),
                        xEnd: .value("End", binEnd(bar)),
                        y: .value("Normal", formatter.precipitationValue(bar.normal ?? 0))
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(t.ink)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: unit, count: labelStride)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(label(date))
                            .font(t.look == .liquid ? .caption2 : t.font(.label, 10, relativeTo: .caption2))
                            .foregroundStyle(t.ink2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(t.grid)
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(axisLabel(amount))
                            .font(t.look == .liquid ? .caption2 : t.font(.label, 10, relativeTo: .caption2))
                            .foregroundStyle(t.ink2)
                    }
                }
            }
        }
        .chartYScale(domain: 0...yMaximum)
    }

    private var unit: Calendar.Component {
        switch granularity {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }

    private var labelStride: Int {
        let count = bars.count
        switch granularity {
        case .day: return count <= 7 ? 1 : max(1, count / 5)
        case .week: return max(1, count / 5)
        case .month: return count <= 6 ? 1 : max(1, count / 6)
        case .year: return max(1, count / 5)
        }
    }

    private func label(_ date: Date) -> String {
        let timeZone = Calendar.current.timeZone
        switch granularity {
        case .day: return bars.count <= 7 ? formatter.weekdayShort(date, timeZone: timeZone) : formatter.monthDay(date, timeZone: timeZone)
        case .week: return formatter.monthDay(date, timeZone: timeZone)
        case .month: return bars.count > 13 ? formatter.monthYear(date, timeZone: timeZone) : formatter.monthShort(date, timeZone: timeZone)
        case .year: return formatter.year(date, timeZone: timeZone)
        }
    }

    private func binStart(_ bar: RainfallRecord.Bar) -> Date {
        let date = chartDate(bar.start, calendar: calendar)
        return Calendar.current.dateInterval(of: unit, for: date)?.start ?? date
    }

    private func binEnd(_ bar: RainfallRecord.Bar) -> Date {
        let date = chartDate(bar.start, calendar: calendar)
        return Calendar.current.dateInterval(of: unit, for: date)?.end ?? date
    }

    private var yMaximum: Double {
        let values = bars.map { formatter.precipitationValue(max($0.amount, $0.normal ?? 0)) }
        let minimum = formatter.units.precipitation == .inches ? 0.25 : 5
        return max((values.max() ?? 0) * 1.15, minimum)
    }

    private func axisLabel(_ value: Double) -> String {
        if formatter.units.precipitation == .inches {
            return String(format: yMaximum < 1 ? "%.2f" : "%.1f", value)
        }
        return String(format: "%.0f", value)
    }
}

private struct CumulativeRainChart: View {
    @Environment(\.lookTokens) private var t
    let points: [RainfallRecord.CumulativePoint]
    let formatter: WeatherFormatter
    let calendar: Calendar

    var body: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Date", chartDate(point.date, calendar: calendar)),
                    yStart: .value("Base", 0.0),
                    yEnd: .value("Total", formatter.precipitationValue(point.total))
                )
                .foregroundStyle(LinearGradient(colors: [t.rain.opacity(0.45), t.rain.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                LineMark(
                    x: .value("Date", chartDate(point.date, calendar: calendar)),
                    y: .value("Total", formatter.precipitationValue(point.total)),
                    series: .value("Series", "Observed")
                )
                .foregroundStyle(t.rain)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            if points.contains(where: { $0.normal != nil }) {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Date", chartDate(point.date, calendar: calendar)),
                        y: .value("Normal", formatter.precipitationValue(point.normal ?? 0)),
                        series: .value("Series", "Normal")
                    )
                    .foregroundStyle(t.ink)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(label(date))
                            .font(t.look == .liquid ? .caption2 : t.font(.label, 10, relativeTo: .caption2))
                            .foregroundStyle(t.ink2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(t.grid)
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(String(format: formatter.units.precipitation == .inches ? "%.1f" : "%.0f", amount))
                            .font(t.look == .liquid ? .caption2 : t.font(.label, 10, relativeTo: .caption2))
                            .foregroundStyle(t.ink2)
                    }
                }
            }
        }
    }

    private func label(_ date: Date) -> String {
        let timeZone = Calendar.current.timeZone
        let days = points.count
        if days > 800 { return formatter.year(date, timeZone: timeZone) }
        if days > 120 { return formatter.monthShort(date, timeZone: timeZone) }
        return formatter.monthDay(date, timeZone: timeZone)
    }
}

// MARK: - Statistics

private struct RainStatsGrid: View {
    let summary: RainfallRecord.Summary
    let normals: PrecipitationNormals?
    let formatter: WeatherFormatter
    let timeZone: TimeZone

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            DetailTile(
                title: "Wet Days",
                systemImage: "cloud.rain.fill",
                value: "\(summary.wetDays)",
                detail: "of \(summary.dayCount - summary.missingDays) days had at least \(formatter.precipitation(RainfallRecord.measurable))."
            )
            DetailTile(
                title: "Wettest Day",
                systemImage: "drop.triangle.fill",
                value: summary.wettestDay.map { formatter.precipitation($0.amount) } ?? "None",
                detail: summary.wettestDay.map { formatter.mediumDate($0.date, timeZone: timeZone) } ?? "No measurable precipitation."
            )
            DetailTile(
                title: "Longest Dry Spell",
                systemImage: "sun.max.fill",
                value: summary.longestDrySpell == 1 ? "1 day" : "\(summary.longestDrySpell) days",
                detail: "In a row without measurable precipitation."
            )
            if let normals {
                DetailTile(
                    title: "Yearly Normal",
                    systemImage: "calendar",
                    value: formatter.precipitation(normals.annualTotal),
                    detail: "Average for a whole year, \(String(normals.firstYear))–\(String(normals.lastYear))."
                )
            }
        }
    }
}

/// Days with measurable precipitation, newest first; each opens in the Time Machine.
private struct WetDaysCard: View {
    @Environment(\.lookTokens) private var t
    let summary: RainfallRecord.Summary
    let record: RainfallRecord
    let formatter: WeatherFormatter

    private static let limit = 60

    var body: some View {
        let days = record.eachDay(in: summary.range)
            .reversed()
            .compactMap { record.days[$0] }
            .filter { $0.amount >= RainfallRecord.measurable }
        WeatherCard(title: "Wet Days", systemImage: "list.bullet", accessory: days.isEmpty ? nil : "Tap for hourly details") {
            if days.isEmpty {
                Text("No measurable precipitation in this period.")
                    .font(t.look == .liquid ? .callout : t.font(.text, t.bodySize))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(days.prefix(Self.limit)), id: \.date) { sample in
                        LookRule()
                        NavigationLink(value: sample.date) {
                            HStack {
                                Text(formatter.mediumDate(sample.date, timeZone: record.calendar.timeZone))
                                    .font(t.look == .liquid ? .body : t.font(.text, t.bodySize + 1))
                                Spacer()
                                if let snow = sample.snowfall, snow >= 0.1 {
                                    Image(systemName: "snowflake")
                                        .font(.caption)
                                        .foregroundStyle(t.rainText)
                                }
                                Text(formatter.precipitation(sample.amount))
                                    .font(t.look == .liquid ? .body.weight(.semibold) : t.font(.number, t.bodySize + 1))
                                    .monospacedDigit()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(t.ink3)
                            }
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if days.count > Self.limit {
                    Text("Showing the \(Self.limit) most recent of \(days.count) wet days.")
                        .font(t.look == .liquid ? .caption : t.font(.text, 12))
                        .foregroundStyle(t.ink2)
                }
            }
        }
    }
}
