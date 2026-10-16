import AiSkyKit
import SwiftUI
import WidgetKit

/// Several saved places at a glance (first ones in your library order).
struct LocationsWidget: Widget {
    let kind = "AiSkyLocations"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LocationsTimelineProvider()) { entry in
            WidgetEnvironmentBridge { LocationsWidgetView(entry: entry) }
        }
        .configurationDisplayName("My Places")
        .description("Current conditions for the first places in your library. Reorder places in the app to choose which appear.")
        .supportedFamilies([.systemMedium, .systemLarge])
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

#Preview(as: .systemMedium) {
    LocationsWidget()
} timeline: {
    LocationsEntry.preview()
}
