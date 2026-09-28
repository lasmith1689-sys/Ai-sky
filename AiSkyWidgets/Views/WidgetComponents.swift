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

/// Sky gradient for Home Screen widgets; clear on the Lock Screen.
struct WidgetBackground: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeatherEntry

    var body: some View {
        if family.isAccessory {
            Color.clear
        } else {
            SkyBackground(
                condition: entry.conditions?.condition ?? .partlyCloudy,
                isDaylight: entry.conditions?.isDaylight ?? true
            )
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

    var body: some View {
        VStack(spacing: 3) {
            Text(isFirst ? "Now" : formatter.hour(hour.date, timeZone: timeZone))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            ConditionIcon(hour.condition, isDaylight: hour.isDaylight)
                .font(.system(size: 15))
                .frame(height: 18)
            Text(formatter.temperature(hour.temperature))
                .font(.system(size: 13, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
    }
}
