import Foundation

/// A place the user saved into their library (max ``LocationLibrary/maximumLocations``).
public struct SavedLocation: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// Name that came from search / geocoding, e.g. "Chicago".
    public var placeName: String
    /// Optional user-provided nickname, e.g. "Home" or "Mom's".
    public var customName: String?
    /// Secondary line, e.g. "Illinois, United States".
    public var subtitle: String?
    public var latitude: Double
    public var longitude: Double
    public var timeZoneIdentifier: String?
    /// ISO 3166-1 alpha-2 country code, used to decide which alert/radar services apply.
    public var countryCode: String?
    public var addedAt: Date

    public init(
        id: UUID = UUID(),
        placeName: String,
        customName: String? = nil,
        subtitle: String? = nil,
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String? = nil,
        countryCode: String? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.placeName = placeName
        self.customName = customName
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.countryCode = countryCode
        self.addedAt = addedAt
    }

    /// The name shown in the UI: the nickname if one was set, otherwise the place name.
    public var displayName: String {
        if let customName, !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customName
        }
        return placeName
    }

    /// When a nickname is set, the original place name is shown as context.
    public var displaySubtitle: String? {
        if customName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return [placeName, subtitle].compactMap { $0 }.joined(separator: ", ")
        }
        return subtitle
    }
}

/// The last known device location, shared with the widgets through the App Group.
public struct CurrentLocationSnapshot: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var name: String?
    public var subtitle: String?
    public var timeZoneIdentifier: String?
    public var countryCode: String?
    public var updatedAt: Date

    public init(
        latitude: Double,
        longitude: Double,
        name: String? = nil,
        subtitle: String? = nil,
        timeZoneIdentifier: String? = nil,
        countryCode: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
        self.subtitle = subtitle
        self.timeZoneIdentifier = timeZoneIdentifier
        self.countryCode = countryCode
        self.updatedAt = updatedAt
    }
}

/// A location that weather can be fetched for: either the device location or a saved place.
public struct WeatherLocation: Codable, Hashable, Identifiable, Sendable {
    public static let currentLocationID = "current"

    public var id: String
    public var name: String
    public var subtitle: String?
    public var latitude: Double
    public var longitude: Double
    public var timeZoneIdentifier: String?
    public var countryCode: String?

    public init(
        id: String,
        name: String,
        subtitle: String? = nil,
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String? = nil,
        countryCode: String? = nil
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.countryCode = countryCode
    }

    public init(saved: SavedLocation) {
        self.init(
            id: saved.id.uuidString,
            name: saved.displayName,
            subtitle: saved.displaySubtitle,
            latitude: saved.latitude,
            longitude: saved.longitude,
            timeZoneIdentifier: saved.timeZoneIdentifier,
            countryCode: saved.countryCode
        )
    }

    public static func current(_ snapshot: CurrentLocationSnapshot) -> WeatherLocation {
        WeatherLocation(
            id: currentLocationID,
            name: snapshot.name ?? "My Location",
            subtitle: snapshot.subtitle,
            latitude: snapshot.latitude,
            longitude: snapshot.longitude,
            timeZoneIdentifier: snapshot.timeZoneIdentifier,
            countryCode: snapshot.countryCode
        )
    }

    public var isCurrentLocation: Bool { id == Self.currentLocationID }

    /// Whether U.S.-only services (NWS alerts, NOAA radar) are likely to cover this point.
    public var isLikelyInUnitedStates: Bool {
        if let countryCode {
            return ["US", "PR", "GU", "VI", "AS", "MP"].contains(countryCode.uppercased())
        }
        return GeoMath.isInUnitedStatesCoverage(latitude: latitude, longitude: longitude)
    }

    /// Great-circle distance in kilometers.
    public func distance(toLatitude lat: Double, longitude lon: Double) -> Double {
        GeoMath.distanceKm(lat1: latitude, lon1: longitude, lat2: lat, lon2: lon)
    }
}

public enum GeoMath {
    /// Haversine distance in kilometers.
    public static func distanceKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6371.0088
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }

    /// Rough bounding boxes for NEXRAD coverage (CONUS, Alaska, Hawaii, Puerto Rico, Guam).
    public static func isInUnitedStatesCoverage(latitude: Double, longitude: Double) -> Bool {
        let boxes: [(ClosedRange<Double>, ClosedRange<Double>)] = [
            (24.0...50.0, -125.5 ... -66.0),   // Contiguous U.S.
            (51.0...72.0, -170.0 ... -129.0),  // Alaska
            (18.5...22.6, -161.0 ... -154.0),  // Hawaii
            (17.5...18.8, -67.6 ... -64.5),    // Puerto Rico / USVI
            (13.1...13.8, 144.5...145.1),      // Guam
        ]
        return boxes.contains { $0.0.contains(latitude) && $0.1.contains(longitude) }
    }
}
