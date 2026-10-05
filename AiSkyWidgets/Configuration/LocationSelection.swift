import AiSkyKit
import AppIntents
import WidgetKit

/// A place a widget can show: "My Location" or one of the saved places.
struct LocationEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Location")
    }

    static var defaultQuery: LocationEntityQuery { LocationEntityQuery() }

    let id: String
    let name: String
    let subtitle: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: name),
            subtitle: subtitle.map { LocalizedStringResource(stringLiteral: $0) }
        )
    }

    static let currentLocation = LocationEntity(
        id: WeatherLocation.currentLocationID,
        name: "My Location",
        subtitle: "Wherever you are"
    )
}

/// Offers the device location plus the saved library (shared through the App Group).
struct LocationEntityQuery: EntityQuery {
    func entities(for identifiers: [LocationEntity.ID]) async throws -> [LocationEntity] {
        let all = Self.allEntities()
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [LocationEntity] {
        Self.allEntities()
    }

    func defaultResult() async -> LocationEntity? {
        let store = SharedStore.shared
        if store.loadCurrentLocation() == nil, let first = store.loadSavedLocations().first {
            return LocationEntity(id: first.id.uuidString, name: first.displayName, subtitle: first.displaySubtitle)
        }
        return .currentLocation
    }

    static func allEntities() -> [LocationEntity] {
        [.currentLocation] + SharedStore.shared.loadSavedLocations().map {
            LocationEntity(id: $0.id.uuidString, name: $0.displayName, subtitle: $0.displaySubtitle)
        }
    }
}

struct SelectLocationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Choose Location" }
    static var description: IntentDescription { "Pick your current location or any place saved in Ai Sky." }

    @Parameter(title: "Location")
    var location: LocationEntity?

    init() {}

    init(location: LocationEntity?) {
        self.location = location
    }
}
