import Foundation

public enum LocationLibraryError: Error, Equatable, LocalizedError {
    case limitReached(Int)
    case duplicate(String)

    public var errorDescription: String? {
        switch self {
        case .limitReached(let max):
            return "Your library is full. You can save up to \(max) places. Remove one to add another."
        case .duplicate(let name):
            return "\(name) is already in your library."
        }
    }
}

/// Pure operations on the saved-location library. Persistence lives in ``SharedStore``.
public enum LocationLibrary {
    /// The library holds up to 20 places (the device's own location is extra).
    public static let maximumLocations = 20
    /// Two places closer than this are considered the same.
    public static let duplicateRadiusKm = 0.75

    public static func existing(nearLatitude latitude: Double, longitude: Double, in list: [SavedLocation]) -> SavedLocation? {
        list.first {
            GeoMath.distanceKm(lat1: $0.latitude, lon1: $0.longitude, lat2: latitude, lon2: longitude) < duplicateRadiusKm
        }
    }

    public static func canAdd(to list: [SavedLocation]) -> Bool {
        list.count < maximumLocations
    }

    public static func remainingSlots(in list: [SavedLocation]) -> Int {
        max(0, maximumLocations - list.count)
    }

    /// Appends `location`, enforcing the 20-location limit and rejecting duplicates.
    public static func adding(_ location: SavedLocation, to list: [SavedLocation]) throws -> [SavedLocation] {
        if let existing = existing(nearLatitude: location.latitude, longitude: location.longitude, in: list) {
            throw LocationLibraryError.duplicate(existing.displayName)
        }
        guard canAdd(to: list) else {
            throw LocationLibraryError.limitReached(maximumLocations)
        }
        return list + [location]
    }

    public static func removing(ids: Set<UUID>, from list: [SavedLocation]) -> [SavedLocation] {
        list.filter { !ids.contains($0.id) }
    }

    /// Same semantics as SwiftUI's `move(fromOffsets:toOffset:)`.
    public static func moving(_ list: [SavedLocation], fromOffsets source: IndexSet, toOffset destination: Int) -> [SavedLocation] {
        let moving = source.sorted().compactMap { list.indices.contains($0) ? list[$0] : nil }
        var remaining: [SavedLocation] = []
        var insertionIndex = destination
        for (index, element) in list.enumerated() {
            if source.contains(index) {
                if index < destination { insertionIndex -= 1 }
            } else {
                remaining.append(element)
            }
        }
        insertionIndex = min(max(0, insertionIndex), remaining.count)
        remaining.insert(contentsOf: moving, at: insertionIndex)
        return remaining
    }

    /// Sets (or clears, when `name` is blank) a nickname.
    public static func renaming(id: UUID, to name: String?, in list: [SavedLocation]) -> [SavedLocation] {
        list.map { location in
            guard location.id == id else { return location }
            var copy = location
            let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            copy.customName = trimmed.isEmpty || trimmed == location.placeName ? nil : trimmed
            return copy
        }
    }

    /// Fills in details learned later (e.g. the time zone reported by the weather service).
    public static func updating(id: String, timeZoneIdentifier: String?, in list: [SavedLocation]) -> [SavedLocation] {
        guard let timeZoneIdentifier else { return list }
        return list.map { location in
            guard location.id.uuidString == id, location.timeZoneIdentifier != timeZoneIdentifier else { return location }
            var copy = location
            copy.timeZoneIdentifier = timeZoneIdentifier
            return copy
        }
    }
}
