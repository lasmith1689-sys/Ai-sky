import AiSkyKit
import Foundation
import WidgetKit

// Timeline entries, shared by the widget extension and the app's DEBUG widget gallery.

struct WeatherEntry: TimelineEntry {
    let date: Date
    let location: WeatherLocation?
    let snapshot: WeatherSnapshot?
    let settings: AppSettings
    let errorMessage: String?

    var formatter: WeatherFormatter { settings.formatter }

    /// Conditions projected to this entry's time (entries are scheduled ahead of time).
    var conditions: CurrentConditions? { snapshot?.conditions(at: date) }

    var nextHour: NextHourSummary {
        NextHourSummarizer.summarize(snapshot?.nextHour, now: date, preferProviderText: false)
    }

    var today: DailyForecast? { snapshot?.day(containing: date) }

    var deepLink: URL { deepLink(section: nil) }

    /// Opens the app on this place, optionally scrolled to a forecast section.
    func deepLink(section: String?) -> URL {
        var components = URLComponents()
        components.scheme = "aisky"
        components.host = "forecast"
        components.path = "/" + (location?.id ?? "")
        if let section {
            components.queryItems = [URLQueryItem(name: "section", value: section)]
        }
        return components.url ?? URL(string: "aisky://forecast")!
    }

    /// Sample weather in the look and units saved in the app, for the widget gallery and
    /// placeholders.
    static func preview(date: Date = Date(), settings: AppSettings = SharedStore.shared.loadSettings()) -> WeatherEntry {
        WeatherEntry(
            date: date,
            location: SampleData.location,
            snapshot: SampleData.snapshot(now: date),
            settings: settings,
            errorMessage: nil
        )
    }
}

struct LocationsEntry: TimelineEntry {
    struct Row: Identifiable {
        var id: String { location.id }
        let location: WeatherLocation
        let summary: LocationWeatherSummary?
    }

    let date: Date
    let rows: [Row]
    let settings: AppSettings

    /// Sample places in the look and units saved in the app.
    static func preview(settings: AppSettings = SharedStore.shared.loadSettings()) -> LocationsEntry {
        let rows = ([SampleData.location] + SampleData.savedLocations.map(WeatherLocation.init(saved:))).enumerated().map { index, location in
            Row(location: location, summary: LocationWeatherSummary(
                locationID: location.id, fetchedAt: Date(), timeZoneIdentifier: location.timeZoneIdentifier ?? "UTC",
                temperature: 12 + Double(index * 4), apparentTemperature: nil,
                condition: [SkyCondition.clear, .partlyCloudy, .rain, .cloudy, .snow][index % 5], isDaylight: true,
                high: 18 + Double(index * 3), low: 8 + Double(index * 2), precipitationChance: 0.2, source: .openMeteo))
        }
        return LocationsEntry(date: Date(), rows: rows, settings: settings)
    }
}

