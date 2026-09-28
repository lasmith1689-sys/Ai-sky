import AiSkyKit
import SwiftUI
import WidgetKit

/// Several saved places at a glance (first ones in your library order).
struct LocationsWidget: Widget {
    let kind = "AiSkyLocations"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LocationsTimelineProvider()) { entry in
            LocationsWidgetView(entry: entry)
        }
        .configurationDisplayName("My Places")
        .description("Current conditions for the first places in your library. Reorder places in the app to choose which appear.")
        .supportedFamilies([.systemMedium, .systemLarge])
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

    static func preview() -> LocationsEntry {
        let rows = ([SampleData.location] + SampleData.savedLocations.map(WeatherLocation.init(saved:))).enumerated().map { index, location in
            Row(location: location, summary: LocationWeatherSummary(
                locationID: location.id, fetchedAt: Date(), timeZoneIdentifier: location.timeZoneIdentifier ?? "UTC",
                temperature: 12 + Double(index * 4), apparentTemperature: nil,
                condition: [SkyCondition.clear, .partlyCloudy, .rain, .cloudy, .snow][index % 5], isDaylight: true,
                high: 18 + Double(index * 3), low: 8 + Double(index * 2), precipitationChance: 0.2, source: .openMeteo))
        }
        return LocationsEntry(date: Date(), rows: rows, settings: AppSettings.defaults())
    }
}

struct LocationsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> LocationsEntry {
        .preview()
    }

    func getSnapshot(in context: Context, completion: @escaping (LocationsEntry) -> Void) {
        if context.isPreview {
            completion(.preview())
            return
        }
        Task {
            completion(await load(limit: context.family == .systemLarge ? 6 : 3))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LocationsEntry>) -> Void) {
        Task {
            let entry = await load(limit: context.family == .systemLarge ? 6 : 3)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
        }
    }

    private func load(limit: Int) async -> LocationsEntry {
        let store = SharedStore.shared
        let settings = store.loadSettings()
        let locations = Array(store.loadAllWeatherLocations().prefix(limit))
        let summaries = await WidgetDataLoader.repository.summaries(for: locations, settings: settings, maxAge: 20 * 60)
        let rows = locations.map { LocationsEntry.Row(location: $0, summary: summaries[$0.id]) }
        return LocationsEntry(date: Date(), rows: rows, settings: settings)
    }
}

struct LocationsWidgetView: View {
    let entry: LocationsEntry

    var body: some View {
        let formatter = entry.settings.formatter
        VStack(spacing: 0) {
            if entry.rows.isEmpty {
                Text("Add places in Ai Sky to see them here.")
                    .font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ForEach(Array(entry.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider().overlay(.white.opacity(0.25))
                }
                Link(destination: URL(string: "aisky://forecast/\(row.location.id)")!) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            WidgetLocationName(location: row.location)
                                .font(.subheadline.weight(.semibold))
                            if let summary = row.summary {
                                Text(summary.condition.description)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                        Spacer()
                        if let summary = row.summary {
                            ConditionIcon(summary.condition, isDaylight: summary.isDaylight)
                                .font(.body)
                            Text(formatter.temperature(summary.temperature))
                                .font(.title3.weight(.medium))
                                .frame(minWidth: 40, alignment: .trailing)
                            if let high = summary.high, let low = summary.low {
                                Text("\(formatter.temperature(high)) / \(formatter.temperature(low))")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.75))
                                    .frame(width: 58, alignment: .trailing)
                            }
                        } else {
                            Text("--")
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            Palette.skyGradient(for: entry.rows.first?.summary?.condition ?? .partlyCloudy, isDaylight: entry.rows.first?.summary?.isDaylight ?? true)
        }
    }
}

#Preview(as: .systemMedium) {
    LocationsWidget()
} timeline: {
    LocationsEntry.preview()
}
