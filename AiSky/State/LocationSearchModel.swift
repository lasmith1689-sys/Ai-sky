import AiSkyKit
import Foundation
import MapKit
import Observation

/// City / address search backed by Apple Maps autocomplete.
@MainActor
@Observable
final class LocationSearchModel {
    var query = ""
    private(set) var results: [MKLocalSearchCompletion] = []
    private(set) var resolvingCompletion: MKLocalSearchCompletion?
    var errorMessage: String?

    private let completer = MKLocalSearchCompleter()
    private let delegate = CompleterDelegate()

    init() {
        completer.resultTypes = [.address, .pointOfInterest]
        completer.delegate = delegate
        delegate.onResults = { [weak self] results in
            self?.results = results
        }
        delegate.onError = { [weak self] error in
            let code = (error as? MKError)?.code
            if code != .placemarkNotFound {
                self?.errorMessage = error.localizedDescription
            }
            self?.results = []
        }
    }

    func queryChanged() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            completer.cancel()
            results = []
        } else {
            completer.queryFragment = trimmed
        }
    }

    /// Looks up coordinates, time zone and country for a completion.
    func resolve(_ completion: MKLocalSearchCompletion) async throws -> SavedLocation {
        resolvingCompletion = completion
        defer { resolvingCompletion = nil }
        let request = MKLocalSearch.Request(completion: completion)
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else {
            throw MKError(.placemarkNotFound)
        }
        let placemark = item.placemark
        let coordinate = placemark.coordinate
        let fallbackSubtitle = [placemark.administrativeArea, placemark.country].compactMap { $0 }.joined(separator: ", ")
        let subtitle = completion.subtitle.isEmpty ? fallbackSubtitle : completion.subtitle
        return SavedLocation(
            placeName: completion.title,
            subtitle: subtitle.isEmpty ? nil : subtitle,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timeZoneIdentifier: item.timeZone?.identifier,
            countryCode: placemark.isoCountryCode
        )
    }
}

private final class CompleterDelegate: NSObject, MKLocalSearchCompleterDelegate {
    var onResults: (@MainActor ([MKLocalSearchCompletion]) -> Void)?
    var onError: (@MainActor (Error) -> Void)?

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        MainActor.assumeIsolated { onResults?(results) }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated { onError?(error) }
    }
}
