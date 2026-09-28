import Foundation

/// Active watches, warnings and advisories from the U.S. National Weather Service
/// (https://api.weather.gov — public domain, requires a User-Agent header).
public struct NWSAlertsClient: Sendable {
    let http: HTTPClient

    public init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    public func activeAlerts(latitude: Double, longitude: Double) async throws -> [WeatherAlertInfo] {
        let data = try await http.data(from: Self.alertsURL(latitude: latitude, longitude: longitude), accept: "application/geo+json")
        return try Self.parse(data, now: Date())
    }

    static func alertsURL(latitude: Double, longitude: Double) -> URL {
        // api.weather.gov rejects more than four decimal places.
        let point = String(format: "%.4f,%.4f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
        var components = URLComponents(string: "https://api.weather.gov/alerts/active")!
        components.queryItems = [URLQueryItem(name: "point", value: point)]
        return components.url!
    }

    static func parse(_ data: Data, now: Date) throws -> [WeatherAlertInfo] {
        let collection: NWSAlertCollection
        do {
            collection = try JSONDecoder().decode(NWSAlertCollection.self, from: data)
        } catch {
            throw WeatherServiceError.decoding(String(describing: error))
        }
        return collection.features
            .map { feature -> WeatherAlertInfo in
                let p = feature.properties
                let id = p.id ?? feature.id ?? UUID().uuidString
                return WeatherAlertInfo(
                    id: id,
                    title: p.event ?? "Weather Alert",
                    headline: p.headline,
                    details: p.description.map(cleanNWSText),
                    instruction: p.instruction.map(cleanNWSText),
                    severity: AlertSeverity(nwsValue: p.severity),
                    source: p.senderName ?? "National Weather Service",
                    region: p.areaDesc,
                    effective: parseDate(p.onset) ?? parseDate(p.effective),
                    expires: parseDate(p.ends) ?? parseDate(p.expires),
                    detailsURL: (feature.id ?? p.id).flatMap { $0.hasPrefix("http") ? URL(string: $0) : nil }
                )
            }
            .filter { $0.isActive(at: now) }
            .sorted { $0.severity > $1.severity }
    }

    /// NWS text uses hard line wraps; keep paragraph breaks but unwrap the lines.
    static func cleanNWSText(_ text: String) -> String {
        text.components(separatedBy: "\n\n")
            .map { $0.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}

struct NWSAlertCollection: Decodable {
    let features: [Feature]

    struct Feature: Decodable {
        let id: String?
        let properties: Properties
    }

    struct Properties: Decodable {
        let id: String?
        let areaDesc: String?
        let effective: String?
        let onset: String?
        let expires: String?
        let ends: String?
        let severity: String?
        let event: String?
        let senderName: String?
        let headline: String?
        let description: String?
        let instruction: String?
    }
}
