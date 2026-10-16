import Foundation

/// The app's visual style, picked in Settings and shared with the widgets through the App Group.
public enum Look: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Condition skies and Liquid Glass cards: the Apple-style option.
    case liquid
    /// True black, hairline rules, ultralight numerals and one accent for rain.
    case obsidian
    /// Graphite panels and a range gauge dial. The default.
    case instrument
    /// A newspaper weather column on warm paper.
    case editorial
    /// The day as a vertical timeline ribbon on deep navy.
    case horizon
    /// Big color blocks and a retro stripe.
    case chroma

    /// New installs, and settings saved before looks existed, start here.
    public static let `default`: Look = .instrument

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .liquid: return "Liquid"
        case .obsidian: return "Obsidian"
        case .instrument: return "Instrument"
        case .editorial: return "Editorial"
        case .horizon: return "Horizon"
        case .chroma: return "Chroma '74"
        }
    }

    /// One line for the Settings picker and VoiceOver.
    public var summary: String {
        switch self {
        case .liquid: return "Condition skies and Liquid Glass"
        case .obsidian: return "True black with hairline rules"
        case .instrument: return "Graphite panels and a range dial"
        case .editorial: return "A newspaper weather column"
        case .horizon: return "Your day as a timeline"
        case .chroma: return "Big color blocks, 1974 style"
        }
    }

    /// `nil` or an id this build doesn't know (from a newer or older version) gives the default.
    public init(id: String?) {
        self = id.flatMap(Look.init(rawValue:)) ?? .default
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Look(id: try? container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
