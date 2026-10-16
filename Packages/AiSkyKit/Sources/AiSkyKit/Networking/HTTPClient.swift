import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum WeatherServiceError: Error, LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int, String?)
    case decoding(String)
    case noData
    case weatherKitUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The weather service returned an unexpected response."
        case .httpStatus(let code, let reason):
            if let reason, !reason.isEmpty { return "Weather service error \(code): \(reason)" }
            return "Weather service error \(code)."
        case .decoding(let detail):
            return "Couldn't read weather data (\(detail))."
        case .noData:
            return "No weather data is available for this location."
        case .weatherKitUnavailable(let detail):
            return "Apple Weather is unavailable: \(detail)"
        }
    }
}

/// Minimal async HTTP client with sensible timeouts and a descriptive User-Agent
/// (required by api.weather.gov and good manners elsewhere).
public struct HTTPClient: Sendable {
    public static let defaultUserAgent = "AiSky/1.0 (+https://github.com/lasmith1689-sys/Ai-sky)"

    public var userAgent: String
    public var timeout: TimeInterval

    public init(userAgent: String = HTTPClient.defaultUserAgent, timeout: TimeInterval = 20) {
        self.userAgent = userAgent
        self.timeout = timeout
    }

    public func data(from url: URL, accept: String = "application/json") async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WeatherServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WeatherServiceError.httpStatus(http.statusCode, Self.errorReason(from: data))
        }
        return data
    }

    public func decode<T: Decodable>(_ type: T.Type, from url: URL, accept: String = "application/json") async throws -> T {
        let data = try await data(from: url, accept: accept)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw WeatherServiceError.decoding(String(describing: error))
        }
    }

    /// Open-Meteo returns `{"error": true, "reason": "..."}`; NWS returns `{"detail": "..."}`.
    static func errorReason(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (object["reason"] as? String) ?? (object["detail"] as? String) ?? (object["title"] as? String)
    }
}
