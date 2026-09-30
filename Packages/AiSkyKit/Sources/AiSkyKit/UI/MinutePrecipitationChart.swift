import Foundation

/// A point on the next-hour chart: minutes from now and a 0...1.1 display value.
public struct MinuteChartPoint: Identifiable, Sendable, Equatable {
    public var id: Double { minute }
    public var minute: Double
    public var value: Double
    public var kind: PrecipitationKind
    public var chance: Double?
}

public enum MinuteChartData {
    /// One point per minute for the next hour. 15-minute data is interpolated between the
    /// middle of each interval so the curve looks natural.
    public static func points(for forecast: NextHourForecast, now: Date) -> [MinuteChartPoint] {
        let samples = forecast.window(from: now, duration: 3600 + forecast.resolution)
        guard !samples.isEmpty else { return [] }

        if forecast.isMinuteByMinute {
            return samples.compactMap { sample in
                let minute = sample.date.timeIntervalSince(now) / 60
                guard minute >= -0.99, minute <= 60 else { return nil }
                return MinuteChartPoint(
                    minute: max(0, minute),
                    value: PrecipitationIntensity.chartValue(millimetersPerHour: sample.intensity),
                    kind: sample.kind,
                    chance: sample.chance
                )
            }
        }

        // Coarse data: anchor each value at the middle of its interval and interpolate.
        let half = forecast.resolution / 2
        let anchors = samples.map { sample -> (minute: Double, value: Double, kind: PrecipitationKind) in
            ((sample.date.addingTimeInterval(half).timeIntervalSince(now)) / 60,
             PrecipitationIntensity.chartValue(millimetersPerHour: sample.intensity),
             sample.kind)
        }
        var points: [MinuteChartPoint] = []
        for minute in stride(from: 0.0, through: 60.0, by: 1.0) {
            let value: Double
            let kind: PrecipitationKind
            if minute <= anchors[0].minute {
                value = anchors[0].value
                kind = anchors[0].kind
            } else if minute >= anchors[anchors.count - 1].minute {
                value = anchors[anchors.count - 1].value
                kind = anchors[anchors.count - 1].kind
            } else {
                let upper = anchors.firstIndex { $0.minute >= minute }!
                let a = anchors[upper - 1]
                let b = anchors[upper]
                let t = (minute - a.minute) / max(b.minute - a.minute, 0.001)
                value = a.value + (b.value - a.value) * t
                kind = t < 0.5 ? a.kind : b.kind
            }
            points.append(MinuteChartPoint(minute: minute, value: value, kind: kind, chance: nil))
        }
        return points
    }
}

#if canImport(SwiftUI) && canImport(Charts)
import Charts
import SwiftUI

/// Dark Sky style "next hour" precipitation graph with LIGHT / MED / HEAVY guide lines.
public struct MinutePrecipitationChart: View {
    public var forecast: NextHourForecast
    public var now: Date
    public var showsGuides: Bool
    public var showsAxis: Bool
    public var tint: Color
    /// Guide lines, grid and axis labels (white on the sky by default).
    public var chrome: Color
    public var labelFont: Font

    public init(
        forecast: NextHourForecast, now: Date = Date(), showsGuides: Bool = true, showsAxis: Bool = true,
        tint: Color? = nil, chrome: Color = .white, labelFont: Font = .caption2
    ) {
        self.forecast = forecast
        self.now = now
        self.showsGuides = showsGuides
        self.showsAxis = showsAxis
        let dominant = forecast.minutes.first { $0.kind != .none }?.kind ?? .rain
        self.tint = tint ?? Palette.precipitation(dominant)
        self.chrome = chrome
        self.labelFont = labelFont
    }

    public var body: some View {
        if showsAxis {
            chart.chartXAxis {
                AxisMarks(values: [0, 10, 20, 30, 40, 50, 60]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(chrome.opacity(0.15))
                    AxisValueLabel {
                        if let minute = value.as(Double.self) {
                            Text(minute == 0 ? "Now" : "\(Int(minute))m")
                                .font(labelFont)
                                .foregroundStyle(chrome.opacity(0.7))
                        }
                    }
                }
            }
        } else {
            chart.chartXAxis(.hidden)
        }
    }

    private var chart: some View {
        let points = MinuteChartData.points(for: forecast, now: now)
        let lines = showsGuides ? guides : []
        return Chart {
            ForEach(lines) { guide in
                RuleMark(y: .value("Intensity", guide.value))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(chrome.opacity(0.3))
                    .annotation(position: .top, alignment: .leading, spacing: 1) {
                        Text(guide.label)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(chrome.opacity(0.55))
                    }
            }
            ForEach(points) { point in
                AreaMark(
                    x: .value("Minute", point.minute),
                    y: .value("Intensity", point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                )
                LineMark(
                    x: .value("Minute", point.minute),
                    y: .value("Intensity", point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartYScale(domain: 0...1.1)
        .chartXScale(domain: 0...60)
        .chartYAxis(.hidden)
        .accessibilityLabel("Precipitation intensity for the next hour")
    }

    struct GuideLine: Identifiable {
        var label: String
        var value: Double
        var id: String { label }
    }

    private var guides: [GuideLine] {
        [GuideLine(label: "LIGHT", value: 1.0 / 3), GuideLine(label: "MED", value: 2.0 / 3), GuideLine(label: "HEAVY", value: 1.0)]
    }
}
#endif
