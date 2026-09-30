import AiSkyKit
import SwiftUI
import WidgetKit

extension WidgetFamily {
    var isAccessory: Bool {
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return true
        default:
            return false
        }
    }
}

// MARK: Family and rendering mode

private struct WidgetLayoutFamilyKey: EnvironmentKey {
    static let defaultValue: WidgetFamily = .systemSmall
}

private struct WidgetInkModeKey: EnvironmentKey {
    static let defaultValue: WidgetRenderingMode = .fullColor
}

extension EnvironmentValues {
    /// The widget's family. Widget views read this rather than the system value so the app's
    /// DEBUG widget gallery can set it (see `WidgetEnvironmentBridge`).
    var widgetLayoutFamily: WidgetFamily {
        get { self[WidgetLayoutFamilyKey.self] }
        set { self[WidgetLayoutFamilyKey.self] = newValue }
    }

    /// How the system renders the widget: full color, tinted (accented) or vibrant.
    var widgetInkMode: WidgetRenderingMode {
        get { self[WidgetInkModeKey.self] }
        set { self[WidgetInkModeKey.self] = newValue }
    }
}

/// Passes the system's widget family and rendering mode down to the widget views.
struct WidgetEnvironmentBridge<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(\.widgetLayoutFamily, family)
            .environment(\.widgetInkMode, renderingMode)
    }
}

extension WeatherEntry {
    /// Tokens of the look picked in the app.
    var tokens: LookTokens { LookTokens.tokens(for: settings.look) }
}

extension LookTokens {
    /// These tokens for a widget rendering mode. In full color the look's own inks and pages;
    /// tinted (accented) and vibrant modes color the widget themselves, keeping only each view's
    /// opacity, so inks become levels of the primary color, the page goes clear and colored
    /// fills (temperature gradients) give way to shapes.
    func adapted(to mode: WidgetRenderingMode) -> LookTokens {
        guard mode != .fullColor else { return self }
        var tokens = self
        tokens.ink = .primary
        tokens.ink2 = .primary.opacity(0.75)
        tokens.ink3 = .primary.opacity(0.6)
        tokens.rain = .primary
        tokens.rainText = .primary
        tokens.now = .primary
        tokens.sun = .primary
        tokens.accent = .primary
        tokens.chartLine = .primary
        tokens.chartArea = .primary.opacity(0.3)
        tokens.track = .primary.opacity(0.25)
        tokens.line = .primary.opacity(0.25)
        tokens.rule = .primary.opacity(0.35)
        tokens.grid = .primary.opacity(0.15)
        tokens.background = .clear
        tokens.surface = .clear
        tokens.surfaceAlt = .clear
        tokens.usesTemperatureColors = false
        return tokens
    }
}

/// The look's page for Home Screen widgets (the condition sky for Liquid); clear on the Lock Screen
/// and in tinted and vibrant modes, where the system draws the background.
struct WidgetBackground: View {
    let entry: WeatherEntry

    var body: some View {
        LookWidgetBackground(
            tokens: entry.tokens,
            condition: entry.conditions?.condition ?? .partlyCloudy,
            isDaylight: entry.conditions?.isDaylight ?? true
        )
    }
}

struct LookWidgetBackground: View {
    @Environment(\.widgetLayoutFamily) private var family
    @Environment(\.widgetInkMode) private var mode
    let tokens: LookTokens
    let condition: SkyCondition
    let isDaylight: Bool

    var body: some View {
        if family.isAccessory || mode != .fullColor {
            Color.clear
        } else if tokens.usesSky {
            SkyBackground(condition: condition, isDaylight: isDaylight)
        } else {
            tokens.background
        }
    }
}

/// Condition symbol in the look's style: full color on the sky, a line glyph elsewhere (and in
/// tinted and vibrant modes).
struct WidgetConditionIcon: View {
    @Environment(\.widgetInkMode) private var mode
    let condition: SkyCondition
    var isDaylight = true
    let tokens: LookTokens

    var body: some View {
        if tokens.look == .liquid && mode == .fullColor {
            ConditionIcon(condition, isDaylight: isDaylight)
        } else {
            OutlineConditionIcon(condition, isDaylight: isDaylight)
                .foregroundStyle(tokens.look == .chroma && mode == .fullColor ? ChromaPalette.cobalt : tokens.ink2)
        }
    }
}

/// Shown when there's nothing to display yet.
struct WidgetEmptyView: View {
    @Environment(\.widgetLayoutFamily) private var family
    let entry: WeatherEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(message)
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "cloud.sun")
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: entry.location == nil ? "location.slash" : "icloud.slash")
                    .font(.title2)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var message: String {
        if entry.location == nil {
            return "Open Ai Sky to choose a location"
        }
        return entry.errorMessage == nil ? "Loading weather…" : "Weather unavailable"
    }
}

/// "Chicago" with a location arrow for the device location.
struct WidgetLocationName: View {
    let location: WeatherLocation

    var body: some View {
        HStack(spacing: 3) {
            Text(location.name)
                .lineLimit(1)
            if location.isCurrentLocation {
                Image(systemName: "location.fill")
                    .font(.system(size: 8))
            }
        }
    }
}

/// A compact column for hourly strips in widgets.
struct WidgetHourColumn: View {
    let hour: HourlyForecast
    let formatter: WeatherFormatter
    let timeZone: TimeZone
    let isFirst: Bool
    let tokens: LookTokens

    var body: some View {
        VStack(spacing: 3) {
            Group {
                if tokens.look == .liquid {
                    Text(isFirst ? "Now" : formatter.hour(hour.date, timeZone: timeZone))
                        .font(.system(size: 10, weight: .medium))
                } else {
                    Text(isFirst ? "Now" : LookClock.hour(hour.date, timeZone: timeZone, tokens: tokens, formatter: formatter))
                        .lookLabel(tokens, size: 10, color: isFirst && tokens.look == .instrument ? tokens.now : tokens.ink2, tracking: 0.5)
                }
            }
            .foregroundStyle(tokens.ink2)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            WidgetConditionIcon(condition: hour.condition, isDaylight: hour.isDaylight, tokens: tokens)
                .font(.system(size: 15))
                .frame(height: 18)
            Text(formatter.temperature(hour.temperature))
                .font(tokens.look == .liquid ? .system(size: 13, weight: .semibold) : tokens.font(.textStrong, 13))
        }
        .frame(maxWidth: .infinity)
    }
}
