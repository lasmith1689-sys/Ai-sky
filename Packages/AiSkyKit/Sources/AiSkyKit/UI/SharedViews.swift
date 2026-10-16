#if canImport(SwiftUI)
import SwiftUI

/// SF Symbol for a condition, in full color.
public struct ConditionIcon: View {
    public var condition: SkyCondition
    public var isDaylight: Bool
    public var multicolor: Bool

    public init(_ condition: SkyCondition, isDaylight: Bool = true, multicolor: Bool = true) {
        self.condition = condition
        self.isDaylight = isDaylight
        self.multicolor = multicolor
    }

    public var body: some View {
        Image(systemName: condition.symbolName(isDaylight: isDaylight))
            .symbolRenderingMode(multicolor ? .multicolor : .hierarchical)
            .accessibilityLabel(condition.description)
    }
}

/// Capsule showing a day's low→high range within the week's overall range (Dark Sky / Apple style).
public struct TemperatureRangeBar: View {
    public var low: Double
    public var high: Double
    public var rangeLow: Double
    public var rangeHigh: Double
    public var current: Double?
    public var trackColor: Color

    public init(low: Double, high: Double, rangeLow: Double, rangeHigh: Double, current: Double? = nil, trackColor: Color = .white.opacity(0.15)) {
        self.low = low
        self.high = high
        self.rangeLow = rangeLow
        self.rangeHigh = rangeHigh
        self.current = current
        self.trackColor = trackColor
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let span = max(rangeHigh - rangeLow, 1)
            let start = CGFloat((low - rangeLow) / span) * width
            let end = CGFloat((high - rangeLow) / span) * width
            let barWidth = max(end - start, proxy.size.height)
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor)
                Capsule()
                    .fill(Palette.temperatureGradient(low: low, high: high))
                    .frame(width: barWidth)
                    .offset(x: min(start, width - barWidth))
                if let current {
                    let x = CGFloat((min(max(current, rangeLow), rangeHigh) - rangeLow) / span) * width
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
                        .frame(width: proxy.size.height + 2, height: proxy.size.height + 2)
                        .offset(x: min(max(x - (proxy.size.height + 2) / 2, 0), width - proxy.size.height - 2))
                }
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

/// Condition-dependent sky gradient used behind forecasts and widgets.
public struct SkyBackground: View {
    public var condition: SkyCondition
    public var isDaylight: Bool

    public init(condition: SkyCondition, isDaylight: Bool) {
        self.condition = condition
        self.isDaylight = isDaylight
    }

    public var body: some View {
        Palette.skyGradient(for: condition, isDaylight: isDaylight)
    }
}
#endif
