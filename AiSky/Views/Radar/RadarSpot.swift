import AiSkyKit
import CoreLocation
import SwiftUI

/// A spot the user touched and held on the radar map (Precip's "rain totals anywhere").
struct RadarSpot: Identifiable, Equatable {
    let id = UUID()
    var coordinate: CLLocationCoordinate2D
    var name: String?
    var subtitle: String?
    var timeZoneIdentifier: String?
    var countryCode: String?

    static func == (lhs: RadarSpot, rhs: RadarSpot) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.subtitle == rhs.subtitle
            && lhs.timeZoneIdentifier == rhs.timeZoneIdentifier
    }

    var displayName: String { name ?? "Dropped Pin" }

    var timeZone: TimeZone { timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current }

    var coordinateText: String {
        String(format: "%.3f°, %.3f°", coordinate.latitude, coordinate.longitude)
    }

    var weatherLocation: WeatherLocation {
        WeatherLocation(
            id: "spot-\(id.uuidString)",
            name: displayName,
            subtitle: subtitle,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timeZoneIdentifier: timeZoneIdentifier,
            countryCode: countryCode
        )
    }

    var savedLocation: SavedLocation {
        SavedLocation(
            placeName: displayName,
            subtitle: subtitle,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timeZoneIdentifier: timeZoneIdentifier,
            countryCode: countryCode
        )
    }

    /// The Time Machine opens on the day before today, local to the spot.
    var yesterday: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: -1, to: today) ?? today
    }

    /// Adds a place name, region and time zone from reverse geocoding.
    func resolvingPlace() async -> RadarSpot {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            return self
        }
        var resolved = self
        resolved.name = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.name
            ?? placemark.inlandWater ?? placemark.ocean
        let region = [placemark.administrativeArea, placemark.country].compactMap { $0 }.joined(separator: ", ")
        resolved.subtitle = region.isEmpty ? nil : region
        resolved.timeZoneIdentifier = placemark.timeZone?.identifier
        resolved.countryCode = placemark.isoCountryCode
        return resolved
    }
}

/// Actions for a touched-and-held spot: its rainfall history, the Time Machine, or saving it.
struct SpotCard: View {
    @Environment(AppModel.self) private var model
    let spot: RadarSpot
    let onShow: (ForecastSheet) -> Void
    let onClose: () -> Void

    @State private var message: String?
    @State private var isSaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(spot.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(spot.subtitle ?? spot.coordinateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            HStack(spacing: 8) {
                action("Rainfall", systemImage: "chart.bar.xaxis") { onShow(.rainHistory) }
                action("Time Machine", systemImage: "clock.arrow.circlepath") { onShow(.timeMachine) }
                action(isSaved ? "Saved" : "Save", systemImage: isSaved ? "checkmark" : "plus") { save() }
                    .disabled(isSaved || !model.canAddLocation)
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func action(_ title: String, systemImage: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func save() {
        do {
            try model.addLocation(spot.savedLocation)
            isSaved = true
            message = "Saved to your locations."
        } catch {
            message = error.localizedDescription
        }
    }
}
