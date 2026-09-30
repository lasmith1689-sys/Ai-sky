#if canImport(SwiftUI)
import SwiftUI

/// Marker for the current temperature on a range bar.
public enum RangeMarker {
    case none
    /// A dot with a ring in the background color, so it separates from the segment.
    case dot(Color, ring: Color)
    /// A thin vertical tick (Obsidian).
    case tick(Color)
}

/// A day's low-to-high span within the week's span: a flat segment on a track, or the
/// temperature gradient when the look uses temperature colors.
public struct LookRangeBar: View {
    public var low: Double
    public var high: Double
    public var rangeLow: Double
    public var rangeHigh: Double
    public var current: Double?
    public var height: CGFloat
    public var fill: Color
    public var track: Color
    public var gradient: Bool
    public var marker: RangeMarker
    public var rounded: Bool

    public init(
        low: Double, high: Double, rangeLow: Double, rangeHigh: Double, current: Double? = nil,
        height: CGFloat = 4, fill: Color, track: Color, gradient: Bool = false,
        marker: RangeMarker = .none, rounded: Bool = true
    ) {
        self.low = low
        self.high = high
        self.rangeLow = rangeLow
        self.rangeHigh = rangeHigh
        self.current = current
        self.height = height
        self.fill = fill
        self.track = track
        self.gradient = gradient
        self.marker = marker
        self.rounded = rounded
    }

    private var markerHeight: CGFloat {
        switch marker {
        case .none: return height
        case .dot: return height + 5
        case .tick: return max(height + 6, 9)
        }
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let span = max(rangeHigh - rangeLow, 1)
            let start = CGFloat((low - rangeLow) / span) * width
            let end = CGFloat((high - rangeLow) / span) * width
            let barWidth = max(end - start, height)
            let barX = min(max(start, 0), max(width - barWidth, 0))
            let midY = proxy.size.height / 2
            ZStack(alignment: .topLeading) {
                shape.fill(track)
                    .frame(width: width, height: rounded ? height : 1)
                    .offset(y: midY - (rounded ? height : 1) / 2)
                Group {
                    if gradient {
                        shape.fill(Palette.temperatureGradient(low: low, high: high))
                    } else {
                        shape.fill(fill)
                    }
                }
                .frame(width: barWidth, height: height)
                .offset(x: barX, y: midY - height / 2)
                if let current {
                    let x = CGFloat((min(max(current, rangeLow), rangeHigh) - rangeLow) / span) * width
                    switch marker {
                    case .none:
                        EmptyView()
                    case .dot(let color, let ring):
                        let size = height + 5
                        Circle()
                            .fill(color)
                            .padding(1.5)
                            .background(Circle().fill(ring))
                            .frame(width: size, height: size)
                            .offset(x: min(max(x - size / 2, 0), width - size), y: midY - size / 2)
                    case .tick(let color):
                        Rectangle()
                            .fill(color)
                            .frame(width: 1, height: markerHeight)
                            .offset(x: min(max(x - 0.5, 0), width - 1), y: midY - markerHeight / 2)
                    }
                }
            }
            .frame(width: width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(height: current == nil ? height : markerHeight)
        .accessibilityHidden(true)
    }

    private var shape: some Shape {
        RoundedRectangle(cornerRadius: rounded ? height / 2 : 0, style: .continuous)
    }
}

/// Minute-by-minute precipitation as bars (2 minutes each for 30 bars); dry stretches are stubs.
public struct MinuteBars: View {
    public var forecast: NextHourForecast
    public var now: Date
    public var count: Int
    public var spacing: CGFloat
    public var wetColor: Color
    public var dryColor: Color
    public var dryHeight: CGFloat
    public var cornerRadius: CGFloat

    public init(
        forecast: NextHourForecast, now: Date, count: Int = 30, spacing: CGFloat = 3,
        wetColor: Color, dryColor: Color, dryHeight: CGFloat = 2, cornerRadius: CGFloat = 2
    ) {
        self.forecast = forecast
        self.now = now
        self.count = count
        self.spacing = spacing
        self.wetColor = wetColor
        self.dryColor = dryColor
        self.dryHeight = dryHeight
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        let values = MinuteChartData.bars(for: forecast, now: now, count: count)
        GeometryReader { proxy in
            let maxHeight = proxy.size.height
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    let wet = value >= MinuteChartData.wetThreshold
                    UnevenRoundedRectangle(
                        topLeadingRadius: wet ? cornerRadius : 0,
                        topTrailingRadius: wet ? cornerRadius : 0,
                        style: .continuous
                    )
                    .fill(wet ? wetColor : dryColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: wet ? max(dryHeight, CGFloat(min(value, 1)) * maxHeight) : dryHeight)
                }
            }
            .frame(width: proxy.size.width, height: maxHeight, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}

/// A slim vertical capsule filled to a precipitation chance.
public struct ChanceCapsule: View {
    public var chance: Double?
    public var fill: Color
    public var track: Color
    public var width: CGFloat
    public var height: CGFloat

    public init(chance: Double?, fill: Color, track: Color, width: CGFloat = 5, height: CGFloat = 26) {
        self.chance = chance
        self.fill = fill
        self.track = track
        self.width = width
        self.height = height
    }

    public var body: some View {
        let value = min(max(chance ?? 0, 0), 1)
        ZStack(alignment: .bottom) {
            Capsule().fill(track)
            if value >= 0.03 {
                RoundedRectangle(cornerRadius: width / 2, style: .continuous)
                    .fill(fill)
                    .frame(height: max(2, CGFloat(value) * height))
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

/// A flat index scale (AQI, UV): a track, a fill up to the value and a marker.
public struct ScaleTrack: View {
    /// 0...1 position of the value.
    public var fraction: Double
    public var fill: Color
    public var track: Color
    public var marker: Color
    /// Category colors to show as a gradient instead of a flat fill.
    public var colors: [Color]?

    public init(fraction: Double, fill: Color, track: Color, marker: Color, colors: [Color]? = nil) {
        self.fraction = fraction
        self.fill = fill
        self.track = track
        self.marker = marker
        self.colors = colors
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let x = CGFloat(min(max(fraction, 0), 1)) * width
            ZStack(alignment: .topLeading) {
                if let colors {
                    Capsule()
                        .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .frame(height: 4)
                        .offset(y: 3)
                } else {
                    Capsule().fill(track).frame(height: 4).offset(y: 3)
                    Capsule().fill(fill).frame(width: max(4, x), height: 4).offset(y: 3)
                }
                RoundedRectangle(cornerRadius: 1)
                    .fill(marker)
                    .frame(width: 2, height: 10)
                    .offset(x: min(max(x - 1, 0), width - 2), y: 0)
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// Monochrome line symbol for a condition ("cloud.sun.fill" becomes "cloud.sun").
public struct OutlineConditionIcon: View {
    public var condition: SkyCondition
    public var isDaylight: Bool

    public init(_ condition: SkyCondition, isDaylight: Bool = true) {
        self.condition = condition
        self.isDaylight = isDaylight
    }

    public static func symbolName(_ condition: SkyCondition, isDaylight: Bool) -> String {
        let name = condition.symbolName(isDaylight: isDaylight)
        return name.hasSuffix(".fill") ? String(name.dropLast(5)) : name
    }

    public var body: some View {
        Image(systemName: Self.symbolName(condition, isDaylight: isDaylight))
            .symbolRenderingMode(.monochrome)
            .accessibilityLabel(condition.description)
    }
}
#endif
