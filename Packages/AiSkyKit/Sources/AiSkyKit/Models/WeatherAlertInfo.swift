import Foundation

public enum AlertSeverity: String, Codable, Sendable, Comparable, CaseIterable {
    case unknown
    case minor
    case moderate
    case severe
    case extreme

    var rank: Int {
        switch self {
        case .unknown: return 0
        case .minor: return 1
        case .moderate: return 2
        case .severe: return 3
        case .extreme: return 4
        }
    }

    public static func < (lhs: AlertSeverity, rhs: AlertSeverity) -> Bool { lhs.rank < rhs.rank }

    public init(nwsValue: String?) {
        switch nwsValue?.lowercased() {
        case "extreme": self = .extreme
        case "severe": self = .severe
        case "moderate": self = .moderate
        case "minor": self = .minor
        default: self = .unknown
        }
    }

    /// 0xRRGGBB accent used for alert banners.
    public var colorHex: UInt32 {
        switch self {
        case .extreme: return 0xB3261E
        case .severe: return 0xE8590C
        case .moderate: return 0xF2A900
        case .minor, .unknown: return 0x5B7083
        }
    }
}

/// A government-issued weather alert (NWS, or via Apple Weather worldwide).
public struct WeatherAlertInfo: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    /// e.g. "Severe Thunderstorm Warning"
    public var title: String
    /// e.g. the NWS headline "... issued September 28 at 2:05PM CDT until 3:00PM CDT by NWS Chicago IL"
    public var headline: String?
    public var details: String?
    public var instruction: String?
    public var severity: AlertSeverity
    public var source: String
    public var region: String?
    public var effective: Date?
    public var expires: Date?
    public var detailsURL: URL?

    public init(
        id: String,
        title: String,
        headline: String? = nil,
        details: String? = nil,
        instruction: String? = nil,
        severity: AlertSeverity,
        source: String,
        region: String? = nil,
        effective: Date? = nil,
        expires: Date? = nil,
        detailsURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.headline = headline
        self.details = details
        self.instruction = instruction
        self.severity = severity
        self.source = source
        self.region = region
        self.effective = effective
        self.expires = expires
        self.detailsURL = detailsURL
    }

    public func isActive(at date: Date = Date()) -> Bool {
        guard let expires else { return true }
        return expires > date
    }
}
