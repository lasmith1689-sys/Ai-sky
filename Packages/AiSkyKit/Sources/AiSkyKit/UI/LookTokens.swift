#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A typeface for one role in a look: a bundled font by PostScript name, or the system font.
public struct LookFace {
    /// PostScript name of a bundled font (see `Fonts/` and `UIAppFonts`), or nil for SF Pro.
    public let postScriptName: String?
    /// Weight and design used when `postScriptName` is nil.
    public let weight: Font.Weight
    public let design: Font.Design

    public static func custom(_ postScriptName: String) -> LookFace {
        LookFace(postScriptName: postScriptName, weight: .regular, design: .default)
    }

    public static func system(_ weight: Font.Weight, design: Font.Design = .default) -> LookFace {
        LookFace(postScriptName: nil, weight: weight, design: design)
    }

    /// Natural line height in ems (ascender plus descender), for matching CSS line heights.
    public var lineHeight: CGFloat {
        guard let name = postScriptName else { return 1.19 }
        if name.hasPrefix("Newsreader") { return 1.0 }
        if name.hasPrefix("Manrope") { return 1.366 }
        if name.hasPrefix("Geist") { return 1.3 }
        if name.hasPrefix("DMMono") { return 1.302 }
        if name.hasPrefix("InstrumentSans") { return 1.22 }
        return 1.2 // Barlow, Bricolage Grotesque
    }

    /// The face at `size` points. Bundled faces scale with Dynamic Type relative to `style` (the
    /// nearest text style when omitted); `fixed` ignores Dynamic Type, for drawings that scale as a
    /// whole. The system face follows the text style's own size so Dynamic Type still applies.
    public func font(_ size: CGFloat, relativeTo style: Font.TextStyle? = nil, fixed: Bool = false) -> Font {
        let style = style ?? LookTokens.textStyle(for: size)
        if let postScriptName {
            return fixed ? .custom(postScriptName, fixedSize: size) : .custom(postScriptName, size: size, relativeTo: style)
        }
        if fixed || size > 36 {
            return .system(size: size, weight: weight, design: design)
        }
        return .system(style, design: design).weight(weight)
    }
}

/// How a look draws a section of the forecast.
public enum LookSurface: Sendable {
    /// iOS 26 Liquid Glass (material on older systems) over the condition sky.
    case glass
    /// Flat fill with a 1 pt border.
    case flat
    /// No card at all: a label, hairline rules and content on the page.
    case hairline
    /// Solid color blocks with generous corners.
    case block
}

/// Colors, type and shapes of one look. The app injects the selected look's tokens into the
/// SwiftUI environment (`\.lookTokens`); widgets build them from the shared settings.
public struct LookTokens {
    public var look: Look
    public var colorScheme: ColorScheme

    // MARK: Colors

    /// Page background (Liquid draws the condition sky instead; see `usesSky`).
    public var background: Color
    /// Card and tile fill.
    public var surface: Color
    /// A second fill for nested or alternating blocks.
    public var surfaceAlt: Color
    /// Card borders, dividers and hairline rules.
    public var line: Color
    /// Strong rules (Editorial's ink rules); the same as `line` elsewhere.
    public var rule: Color
    /// Empty tracks of bars, gauges and capsules.
    public var track: Color
    /// Primary, secondary and tertiary text. Tertiary text keeps at least 4.5:1 contrast on the
    /// look's page and cards (a touch lighter or darker than the mockups where they fell short).
    public var ink: Color
    public var ink2: Color
    public var ink3: Color
    /// Controls, links and selection.
    public var accent: Color
    /// Text and symbols drawn on an `accent` fill.
    public var onAccent: Color
    /// Precipitation fills (bars, areas) and precipitation text.
    public var rain: Color
    public var rainText: Color
    /// Markers for "now" (the gauge needle, the current hour).
    public var now: Color
    /// Sunrise and sunset accents.
    public var sun: Color
    /// Chart series and fills.
    public var chartLine: Color
    public var chartArea: Color
    public var grid: Color
    /// Liquid only: temperature lines and range bars use the warm-to-cool temperature gradient.
    public var usesTemperatureColors: Bool
    /// Liquid only: the page background is the condition sky gradient.
    public var usesSky: Bool

    // MARK: Type

    /// Hero temperature.
    public var display: LookFace
    /// Large text: headlines, the condition line.
    public var headline: LookFace
    public var text: LookFace
    public var textMedium: LookFace
    public var textStrong: LookFace
    /// Small section labels ("NEXT HOUR").
    public var label: LookFace
    /// Values in tiles and rows.
    public var number: LookFace
    /// Large light numerals in tiles.
    public var numberLight: LookFace
    /// Emphasis within text (Editorial's italic serif).
    public var emphasis: LookFace
    /// Default size, case and tracking (em) of section labels.
    public var labelSize: CGFloat
    public var labelCase: Text.Case?
    public var labelTracking: CGFloat
    /// Monospaced or condensed labels read times as 24-hour clocks, as in the mockups.
    public var uses24HourClock: Bool

    // MARK: Shape

    public var surfaceStyle: LookSurface
    public var cardRadius: CGFloat
    public var tileRadius: CGFloat
    public var cardPadding: CGFloat
    /// Horizontal page margin.
    public var gutter: CGFloat
    /// Vertical gap between forecast sections.
    public var sectionSpacing: CGFloat
    /// Body text size in secondary sections.
    public var bodySize: CGFloat
    /// Tint for system switches and sliders (nil keeps the system default).
    public var controlTint: Color?
    /// Liquid only: opacity of the dark sheen under glass cards on a gray sky (0 keeps the light,
    /// clear glass). Set by ``onSky(_:isDaylight:)``.
    public var glassSheen: Double = 0

    /// Liquid on a gray sky: cards carry a dark sheen and secondary text is brighter.
    public var onGraySky: Bool { glassSheen > 0 }

    /// These tokens for content drawn over Liquid's `condition` sky: on gray skies the glass
    /// cards get a dark sheen sized from the sky (``LiquidGlass``) and secondary and tertiary
    /// text brighten so they keep 4.5:1 on it. Blue skies, and every other look, are unchanged.
    public func onSky(_ condition: SkyCondition, isDaylight: Bool) -> LookTokens {
        guard usesSky else { return self }
        var copy = self
        copy.glassSheen = LiquidGlass.sheen(for: condition, isDaylight: isDaylight)
        let gray = copy.glassSheen > 0
        copy.ink2 = gray ? .white.opacity(LiquidGlass.graySkyInk2) : LookTokens.liquid.ink2
        copy.ink3 = gray ? .white.opacity(LiquidGlass.graySkyInk3) : LookTokens.liquid.ink3
        return copy
    }

    /// Label tracking in points at `size`.
    public func tracking(_ size: CGFloat) -> CGFloat { size * labelTracking }

    /// Type roles, so views can ask for "the look's label face at 11 pt".
    public enum Role {
        case display, headline, text, textMedium, textStrong, label, number, numberLight, emphasis
    }

    public func face(_ role: Role) -> LookFace {
        switch role {
        case .display: return display
        case .headline: return headline
        case .text: return text
        case .textMedium: return textMedium
        case .textStrong: return textStrong
        case .label: return label
        case .number: return number
        case .numberLight: return numberLight
        case .emphasis: return emphasis
        }
    }

    public func font(_ role: Role, _ size: CGFloat, relativeTo style: Font.TextStyle? = nil, fixed: Bool = false) -> Font {
        face(role).font(size, relativeTo: style, fixed: fixed)
    }

    /// Colored blocks for Chroma '74's cards. Other looks ignore tones.
    public enum Tone {
        case standard, cobalt, navy, green, mustard
    }

    /// These tokens for content drawn on a `tone` block.
    public func toned(_ tone: Tone) -> LookTokens {
        guard look == .chroma, tone != .standard else { return self }
        var copy = self
        let cream = ChromaPalette.cream
        switch tone {
        case .standard:
            break
        case .mustard:
            copy.surface = ChromaPalette.mustard
            copy.ink = ChromaPalette.navy
            copy.ink2 = ChromaPalette.navy.opacity(0.78)
            copy.ink3 = ChromaPalette.navy.opacity(0.66)
            copy.line = ChromaPalette.navy.opacity(0.18)
            copy.track = ChromaPalette.navy.opacity(0.14)
            copy.rain = ChromaPalette.navy
            copy.rainText = ChromaPalette.navy
            copy.chartLine = ChromaPalette.navy
            copy.chartArea = ChromaPalette.navy.opacity(0.18)
            copy.grid = ChromaPalette.navy.opacity(0.16)
        case .cobalt, .navy, .green:
            copy.surface = tone == .cobalt ? ChromaPalette.cobalt : (tone == .navy ? ChromaPalette.navy : ChromaPalette.green)
            copy.ink = cream
            copy.ink2 = cream.opacity(0.8)
            copy.ink3 = cream.opacity(0.68)
            copy.line = cream.opacity(0.2)
            copy.rule = cream.opacity(0.2)
            copy.track = cream.opacity(0.22)
            copy.rain = tone == .cobalt ? cream : Palette.color(hex: 0x8FB0FF)
            copy.rainText = tone == .cobalt ? cream : Palette.color(hex: 0xA9C2FF)
            copy.accent = tone == .navy ? ChromaPalette.mustard : cream
            copy.onAccent = ChromaPalette.navy
            copy.chartLine = cream
            copy.chartArea = cream.opacity(0.2)
            copy.grid = cream.opacity(0.16)
        }
        return copy
    }

    public static func tokens(for look: Look) -> LookTokens {
        switch look {
        case .liquid: return liquid
        case .obsidian: return obsidian
        case .instrument: return instrument
        case .editorial: return editorial
        case .horizon: return horizon
        case .chroma: return chroma
        }
    }

    /// Text style a point size scales with under Dynamic Type.
    public static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: return .caption2
        case ..<12.5: return .caption
        case ..<14: return .footnote
        case ..<16: return .subheadline
        case ..<17.5: return .callout
        case ..<19: return .body
        case ..<21: return .title3
        case ..<25: return .title2
        case ..<32: return .title
        default: return .largeTitle
        }
    }

    private static func hex(_ value: UInt32, _ opacity: Double = 1) -> Color {
        Palette.color(hex: value, opacity: opacity)
    }

    // MARK: The six looks

    public static let liquid = LookTokens(
        look: .liquid, colorScheme: .dark,
        background: hex(0x2B5EA8), surface: .white.opacity(0.16), surfaceAlt: .white.opacity(0.1),
        line: .white.opacity(0.22), rule: .white.opacity(0.22), track: .white.opacity(0.2),
        ink: .white, ink2: .white.opacity(0.82), ink3: .white.opacity(0.66),
        accent: .white, onAccent: hex(0x1D3F73),
        rain: .white.opacity(0.6), rainText: hex(0xE2F1FF), now: .white, sun: hex(0xFFD9A8),
        chartLine: .white, chartArea: .white.opacity(0.3), grid: .white.opacity(0.16),
        usesTemperatureColors: true, usesSky: true,
        display: .system(.thin), headline: .system(.semibold), text: .system(.regular),
        textMedium: .system(.medium), textStrong: .system(.semibold), label: .system(.semibold),
        number: .system(.medium), numberLight: .system(.light), emphasis: .system(.semibold),
        labelSize: 12, labelCase: .uppercase, labelTracking: 0.02, uses24HourClock: false,
        surfaceStyle: .glass, cardRadius: 26, tileRadius: 22, cardPadding: 16, gutter: 16, sectionSpacing: 12,
        bodySize: 15, controlTint: nil
    )

    public static let obsidian = LookTokens(
        look: .obsidian, colorScheme: .dark,
        background: hex(0x000000), surface: hex(0x0B0B0A), surfaceAlt: hex(0x121211),
        line: hex(0x1F1F1D), rule: hex(0x1F1F1D), track: hex(0x2A2A28),
        ink: hex(0xF4F4F2), ink2: hex(0x8A8A86), ink3: hex(0x767672),
        accent: hex(0xF4F4F2), onAccent: hex(0x000000),
        rain: hex(0x7CC4FF), rainText: hex(0x7CC4FF), now: hex(0xF4F4F2), sun: hex(0x8A8A86),
        chartLine: hex(0xF4F4F2), chartArea: hex(0xF4F4F2, 0.08), grid: hex(0x161615),
        usesTemperatureColors: false, usesSky: false,
        display: .custom("Geist-ExtraLight"), headline: .custom("Geist-Regular"), text: .custom("Geist-Regular"),
        textMedium: .custom("Geist-Medium"), textStrong: .custom("Geist-Medium"), label: .custom("GeistMono-Regular"),
        number: .custom("GeistMono-Regular"), numberLight: .custom("Geist-Light"), emphasis: .custom("Geist-Regular"),
        labelSize: 10, labelCase: .uppercase, labelTracking: 0.16, uses24HourClock: true,
        surfaceStyle: .hairline, cardRadius: 0, tileRadius: 0, cardPadding: 0, gutter: 24, sectionSpacing: 24,
        bodySize: 15, controlTint: hex(0x7CC4FF)
    )

    public static let instrument = LookTokens(
        look: .instrument, colorScheme: .dark,
        background: hex(0x121417), surface: hex(0x1A1D21), surfaceAlt: hex(0x16191C),
        line: hex(0x2A2E34), rule: hex(0x2A2E34), track: hex(0x23272C),
        ink: hex(0xE9E4D8), ink2: hex(0x8B8F96), ink3: hex(0x80858D),
        accent: hex(0xF26B38), onAccent: hex(0x121417),
        rain: hex(0x4C7DFF), rainText: hex(0x7EA3FF), now: hex(0xF26B38), sun: hex(0xE0A15E),
        chartLine: hex(0xE9E4D8), chartArea: hex(0xE9E4D8, 0.08), grid: hex(0x23272C),
        usesTemperatureColors: false, usesSky: false,
        display: .custom("Barlow-Light"), headline: .custom("Barlow-Regular"), text: .custom("Barlow-Regular"),
        textMedium: .custom("Barlow-Medium"), textStrong: .custom("Barlow-SemiBold"), label: .custom("BarlowCondensed-SemiBold"),
        number: .custom("Barlow-Regular"), numberLight: .custom("Barlow-Light"), emphasis: .custom("Barlow-Medium"),
        labelSize: 12, labelCase: .uppercase, labelTracking: 0.18, uses24HourClock: true,
        surfaceStyle: .flat, cardRadius: 18, tileRadius: 14, cardPadding: 16, gutter: 18, sectionSpacing: 10,
        bodySize: 15, controlTint: hex(0xF26B38)
    )

    public static let editorial = LookTokens(
        look: .editorial, colorScheme: .light,
        background: hex(0xF3EFE6), surface: hex(0xF3EFE6), surfaceAlt: hex(0xEBE5D8),
        line: hex(0xD9D2C3), rule: hex(0x17150F), track: hex(0xDDD6C7),
        ink: hex(0x17150F), ink2: hex(0x6E685C), ink3: hex(0x726C60),
        accent: hex(0x2C4DA0), onAccent: hex(0xF3EFE6),
        rain: hex(0x2C4DA0), rainText: hex(0x2C4DA0), now: hex(0x17150F), sun: hex(0xA2672A),
        chartLine: hex(0x17150F), chartArea: hex(0x17150F, 0.06), grid: hex(0xD9D2C3),
        usesTemperatureColors: false, usesSky: false,
        display: .custom("NewsreaderDisplay-Light"), headline: .custom("NewsreaderHeadline-Regular"),
        text: .custom("InstrumentSans-Regular"), textMedium: .custom("InstrumentSans-Medium"),
        textStrong: .custom("InstrumentSans-SemiBold"), label: .custom("InstrumentSans-SemiBold"),
        number: .custom("NewsreaderText-Regular"), numberLight: .custom("NewsreaderDisplay-Light"),
        emphasis: .custom("NewsreaderText-Italic"),
        labelSize: 10.5, labelCase: .uppercase, labelTracking: 0.15, uses24HourClock: false,
        surfaceStyle: .hairline, cardRadius: 0, tileRadius: 0, cardPadding: 0, gutter: 24, sectionSpacing: 22,
        bodySize: 14, controlTint: hex(0x2C4DA0)
    )

    public static let horizon = LookTokens(
        look: .horizon, colorScheme: .dark,
        background: hex(0x0D1320), surface: hex(0x131B2B), surfaceAlt: hex(0x182134),
        line: hex(0x1C2536), rule: hex(0x1C2536), track: hex(0x222C40),
        ink: hex(0xEAF0FA), ink2: hex(0x8793A8), ink3: hex(0x727F95),
        accent: hex(0x7FB8FF), onAccent: hex(0x0D1320),
        rain: hex(0x4F8FF7), rainText: hex(0x7FB8FF), now: hex(0xEAF0FA), sun: hex(0xFFD9A8),
        chartLine: hex(0xEAF0FA), chartArea: hex(0x7FB8FF, 0.12), grid: hex(0x1C2536),
        usesTemperatureColors: false, usesSky: false,
        display: .custom("Manrope-Light"), headline: .custom("Manrope-SemiBold"), text: .custom("Manrope-Regular"),
        textMedium: .custom("Manrope-Medium"), textStrong: .custom("Manrope-SemiBold"), label: .custom("Manrope-Bold"),
        number: .custom("Manrope-Medium"), numberLight: .custom("Manrope-Light"), emphasis: .custom("Manrope-SemiBold"),
        labelSize: 11, labelCase: .uppercase, labelTracking: 0.145, uses24HourClock: false,
        surfaceStyle: .flat, cardRadius: 20, tileRadius: 16, cardPadding: 16, gutter: 20, sectionSpacing: 14,
        bodySize: 14, controlTint: hex(0x4F8FF7)
    )

    public static let chroma = LookTokens(
        look: .chroma, colorScheme: .light,
        background: hex(0xF2EAD8), surface: hex(0xE8DCC2), surfaceAlt: hex(0xDFD1B3),
        line: hex(0x1C2B4B, 0.14), rule: hex(0x1C2B4B, 0.14), track: hex(0x1C2B4B, 0.1),
        ink: hex(0x1C2B4B), ink2: hex(0x47536B), ink3: hex(0x555F73),
        accent: hex(0x2F5BD3), onAccent: hex(0xF2EAD8),
        rain: hex(0x2F5BD3), rainText: hex(0x2F5BD3), now: hex(0xD9582B), sun: hex(0xD9582B),
        chartLine: hex(0x1C2B4B), chartArea: hex(0xE3A62B, 0.35), grid: hex(0x1C2B4B, 0.12),
        usesTemperatureColors: false, usesSky: false,
        display: .custom("BricolageGrotesqueDisplay-Medium"), headline: .custom("BricolageGrotesque-SemiBold"),
        text: .custom("BricolageGrotesque-Regular"), textMedium: .custom("BricolageGrotesque-Medium"),
        textStrong: .custom("BricolageGrotesque-SemiBold"), label: .custom("DMMono-Regular"),
        number: .custom("DMMono-Regular"), numberLight: .custom("BricolageGrotesqueDisplay-Medium"),
        emphasis: .custom("BricolageGrotesque-SemiBold"),
        labelSize: 11, labelCase: .uppercase, labelTracking: 0.14, uses24HourClock: false,
        surfaceStyle: .block, cardRadius: 26, tileRadius: 22, cardPadding: 18, gutter: 12, sectionSpacing: 10,
        bodySize: 15, controlTint: hex(0x2F5BD3)
    )
}

/// Chroma '74's named colors, used by its bespoke views and widgets.
public enum ChromaPalette {
    public static let cream = Palette.color(hex: 0xF2EAD8)
    public static let sand = Palette.color(hex: 0xE8DCC2)
    public static let navy = Palette.color(hex: 0x1C2B4B)
    public static let mustard = Palette.color(hex: 0xE3A62B)
    public static let green = Palette.color(hex: 0x2E5B45)
    public static let orange = Palette.color(hex: 0xD9582B)
    public static let cobalt = Palette.color(hex: 0x2F5BD3)
}

/// Every bundled face, by PostScript name. The debug build checks that each one resolves, since a
/// wrong name or a missing `UIAppFonts` entry silently falls back to the system font.
public enum LookFonts {
    public static let all: [String] = [
        "Barlow-Light", "Barlow-Regular", "Barlow-Medium", "Barlow-SemiBold",
        "BarlowCondensed-Medium", "BarlowCondensed-SemiBold",
        "Geist-ExtraLight", "Geist-Light", "Geist-Regular", "Geist-Medium",
        "GeistMono-Regular", "GeistMono-Medium",
        "NewsreaderDisplay-Light", "NewsreaderHeadline-Regular", "NewsreaderText-Regular",
        "NewsreaderText-Medium", "NewsreaderText-Italic",
        "InstrumentSans-Regular", "InstrumentSans-Medium", "InstrumentSans-SemiBold",
        "Manrope-Light", "Manrope-Regular", "Manrope-Medium", "Manrope-SemiBold", "Manrope-Bold",
        "BricolageGrotesqueDisplay-Medium", "BricolageGrotesque-SemiBold", "BricolageGrotesque-Medium",
        "BricolageGrotesque-Regular",
        "DMMono-Regular", "DMMono-Medium",
    ]

    /// The faces the widget extension bundles (a subset, to keep it small).
    public static let widget: [String] = [
        "Barlow-Light", "Barlow-Regular", "Barlow-SemiBold", "BarlowCondensed-SemiBold",
        "Geist-ExtraLight", "Geist-Regular", "Geist-Medium", "GeistMono-Regular",
        "NewsreaderDisplay-Light", "NewsreaderText-Regular", "NewsreaderText-Italic", "InstrumentSans-Regular", "InstrumentSans-SemiBold",
        "Manrope-Light", "Manrope-Regular", "Manrope-Medium", "Manrope-SemiBold", "Manrope-Bold",
        "BricolageGrotesqueDisplay-Medium", "BricolageGrotesque-SemiBold", "BricolageGrotesque-Regular", "DMMono-Regular",
    ]

    #if canImport(UIKit)
    /// Names among `names` that don't resolve to a font.
    public static func missing(_ names: [String] = all) -> [String] {
        names.filter { UIFont(name: $0, size: 12) == nil }
    }
    #endif
}

private struct LookTokensKey: EnvironmentKey {
    static let defaultValue = LookTokens.tokens(for: .default)
}

extension EnvironmentValues {
    /// Tokens of the selected look.
    public var lookTokens: LookTokens {
        get { self[LookTokensKey.self] }
        set { self[LookTokensKey.self] = newValue }
    }
}

extension View {
    /// Trims (or pads) the text's line box to a CSS line height, so big numerals sit as tightly as
    /// in the mockups: `.cssLineHeight(0.9, size: 148, face: tokens.display)`.
    public func cssLineHeight(_ lineHeight: CGFloat, size: CGFloat, face: LookFace) -> some View {
        padding(.vertical, (lineHeight - face.lineHeight) / 2 * size)
    }

    /// Section label in the look's label face, case and tracking: "NEXT HOUR".
    public func lookLabel(
        _ tokens: LookTokens, size: CGFloat? = nil, color: Color? = nil, face: LookFace? = nil, tracking: CGFloat? = nil
    ) -> some View {
        let size = size ?? tokens.labelSize
        return self
            .font((face ?? tokens.label).font(size))
            .tracking(tracking ?? tokens.tracking(size))
            .textCase(tokens.labelCase)
            .foregroundStyle(color ?? tokens.ink2)
    }
}

/// Clock strings for looks that read time like an instrument (always 24-hour) and the rest
/// (following the phone's setting through the formatter).
public enum LookClock {
    public static func time(_ date: Date, timeZone: TimeZone, tokens: LookTokens, formatter: WeatherFormatter) -> String {
        tokens.uses24HourClock ? twentyFourHour(date, timeZone: timeZone, pattern: "HH:mm") : formatter.time(date, timeZone: timeZone)
    }

    /// "16" or "4 PM".
    public static func hour(_ date: Date, timeZone: TimeZone, tokens: LookTokens, formatter: WeatherFormatter) -> String {
        tokens.uses24HourClock ? twentyFourHour(date, timeZone: timeZone, pattern: "HH") : formatter.hour(date, timeZone: timeZone)
    }

    public static func twentyFourHour(_ date: Date, timeZone: TimeZone, pattern: String) -> String {
        cache.string(from: date, pattern: pattern, timeZone: timeZone)
    }

    private static let cache = FixedFormatCache()
}

/// Thread-safe cache of fixed-pattern `DateFormatter`s.
private final class FixedFormatCache: @unchecked Sendable {
    private var formatters: [String: DateFormatter] = [:]
    private let lock = NSLock()

    func string(from date: Date, pattern: String, timeZone: TimeZone) -> String {
        let key = "\(pattern)|\(timeZone.identifier)"
        lock.lock()
        defer { lock.unlock() }
        let formatter: DateFormatter
        if let cached = formatters[key] {
            formatter = cached
        } else {
            formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = pattern
            formatters[key] = formatter
        }
        return formatter.string(from: date)
    }
}
#endif
