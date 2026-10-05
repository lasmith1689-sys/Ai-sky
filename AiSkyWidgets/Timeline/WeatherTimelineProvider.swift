import AiSkyKit
import SwiftUI
import WidgetKit

/// How often each widget kind refreshes and how its future entries are spaced.
enum WidgetRefreshStyle {
    /// Temperature & conditions: hourly entries from the forecast, refresh every 30 min.
    case conditions
    /// Next-hour precipitation: 5-minute entries so "Rain in 12 min" counts down.
    case nextHour
    /// Air quality / precipitation totals: hourly entries, refresh every hour.
    case slow

    var refreshInterval: TimeInterval {
        switch self {
        case .conditions: return 30 * 60
        case .nextHour: return 20 * 60
        case .slow: return 60 * 60
        }
    }

    func entryDates(from now: Date) -> [Date] {
        switch self {
        case .nextHour:
            return (0..<12).map { now.addingTimeInterval(Double($0) * 5 * 60) }
        case .conditions, .slow:
            // Now, then the top of each of the next four hours.
            let calendar = Calendar(identifier: .gregorian)
            let nextHour = calendar.dateInterval(of: .hour, for: now)?.end ?? now.addingTimeInterval(3600)
            return [now] + (0..<4).map { nextHour.addingTimeInterval(Double($0) * 3600) }
        }
    }
}

struct WeatherTimelineProvider: AppIntentTimelineProvider {
    let style: WidgetRefreshStyle

    func placeholder(in context: Context) -> WeatherEntry {
        .preview()
    }

    func snapshot(for configuration: SelectLocationIntent, in context: Context) async -> WeatherEntry {
        if context.isPreview {
            return .preview()
        }
        let result = await WidgetDataLoader.load(locationID: configuration.location?.id)
        return WeatherEntry(date: Date(), location: result.location, snapshot: result.snapshot, settings: result.settings, errorMessage: result.errorMessage)
    }

    func timeline(for configuration: SelectLocationIntent, in context: Context) async -> Timeline<WeatherEntry> {
        let now = Date()
        let result = await WidgetDataLoader.load(locationID: configuration.location?.id)
        let entries = style.entryDates(from: now).map { date in
            WeatherEntry(date: date, location: result.location, snapshot: result.snapshot, settings: result.settings, errorMessage: result.errorMessage)
        }
        // Retry sooner when there's no data (e.g. offline or no location yet).
        let interval = result.snapshot == nil ? 10 * 60 : style.refreshInterval
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(interval)))
    }

    func recommendations() -> [AppIntentRecommendation<SelectLocationIntent>] {
        []
    }
}
