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

extension WeatherEntry {
    /// Tokens of the look picked in the app.
    var tokens: LookTokens { LookTokens.tokens(for: settings.look) }
}

/// The look's page for Home Screen widgets (the condition sky for Liquid); clear on the Lock Screen.
struct WidgetBackground: View {
    @Environment(\.widgetFamily) private var family
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
    @Environment(\.widgetFamily) private var family
    let tokens: LookTokens
    let condition: SkyCondition
    let isDaylight: Bool

    var body: some View {
        if family.isAccessory {
            Color.clear
        } else if tokens.usesSky {
            SkyBackground(condition: condition, isDaylight: isDaylight)
        } else {
            tokens.background
        }
    }
}

/// Condition symbol in the look's style: full color on the sky, a line glyph elsewhere.
struct WidgetConditionIcon: View {
    let condition: SkyCondition
    var isDaylight = true
    let tokens: LookTokens

    var body: some View {
        if tokens.look == .liquid {
            ConditionIcon(condition, isDaylight: isDaylight)
        } else {
            OutlineConditionIcon(condition, isDaylight: isDaylight)
                .foregroundStyle(tokens.look == .chroma ? ChromaPalette.cobalt : tokens.ink2)
        }
    }
}

/// Shown when there's nothing to display yet.
struct WidgetEmptyView: View {
    @Environment(\.widgetFamily) private var family
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
