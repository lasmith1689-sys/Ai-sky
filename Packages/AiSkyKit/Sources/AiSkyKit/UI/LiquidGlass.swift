import Foundation

/// WCAG relative luminance and contrast for sRGB colors given as 0xRRGGBB.
public enum ColorContrast {
    public typealias RGB = (red: Double, green: Double, blue: Double)

    public static func rgb(_ hex: UInt32) -> RGB {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    /// Relative luminance, 0 (black) to 1 (white).
    public static func luminance(_ color: RGB) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    /// Contrast ratio between two colors, 1 to 21.
    public static func ratio(_ a: RGB, _ b: RGB) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// `color` drawn at `opacity` over `background` (source-over, in sRGB like the renderer).
    public static func blend(_ color: RGB, opacity: Double, over background: RGB) -> RGB {
        (color.red * opacity + background.red * (1 - opacity),
         color.green * opacity + background.green * (1 - opacity),
         color.blue * opacity + background.blue * (1 - opacity))
    }

    public static let white: RGB = (1, 1, 1)
    public static let black: RGB = (0, 0, 0)
}

#if canImport(SwiftUI)
/// How Liquid's glass cards and hero sit on the condition sky.
///
/// Clear glass lets the sky and its clouds through, and over a pale sky white type washes out.
/// So every card gets a sheen under its content, sized from the sky itself: enough to bring a
/// card over the lightest part of that sky (its bottom stop, lifted by the glass highlight and
/// the clouds) down to ``cardTarget``, where white text is about 7:1 and tertiary text (white at
/// 82%) stays above 4.5:1. Gray skies (clouds, wind, fog, rain, snow, sleet, storms, overcast
/// nights) get a black sheen; blue skies (clear and partly cloudy) get a deep blue one, so their
/// cards read as blue glass rather than slate. Where the sky is already dark enough (clear
/// nights) the blue sheen shrinks toward nothing. Apple's guidance for the clear glass variant
/// over bright content is the same idea: a dimming layer under it.
///
/// The hero sits on the sky itself; over the bright clouds of a blue day sky a soft scrim in the
/// sky's own top color keeps it at 3:1 or better (``heroScrim(for:isDaylight:)``).
public enum LiquidGlass {
    public enum Tone: Sendable {
        /// Clear and partly cloudy skies: a deep blue sheen.
        case blue
        /// Every other sky: a black sheen.
        case gray
    }

    public static func tone(for condition: SkyCondition, isDaylight: Bool) -> Tone {
        switch condition.family {
        case .clear, .partlyCloudy: return .blue
        default: return .gray
        }
    }

    /// Opacity of the soft clouds drifting in the sky (the mockup's partly cloudy clouds at full
    /// strength; faint on gray skies, where they would wash out the type; dimmer at night).
    public static func cloudStrength(for condition: SkyCondition, isDaylight: Bool) -> Double {
        let base: Double
        switch condition.family {
        case .partlyCloudy: base = 1
        case .clear: base = 0.3
        default: base = 0.12
        }
        return base * (isDaylight ? 1 : 0.35)
    }

    /// Relative luminance the card behind the text should not exceed.
    public static let cardTarget = 0.10

    /// How much lighter than the sky a card renders before the sheen (the glass highlight and
    /// the faint gray-sky clouds), as a share of the way to white. Measured from CI screenshots
    /// of the cloudy, fog and snow skies: 13% to 18%.
    public static let glassLift = 0.16

    /// Extra lift per unit of cloud strength above the gray-sky clouds (measured on the partly
    /// cloudy sky, where the clouds behind the lower cards lifted them about half way to white).
    public static let cloudLift = 0.4

    /// The gray sheen never drops below this, so dark gray skies still read as that treatment.
    public static let minimumSheen = 0.2
    public static let maximumSheen = 0.95

    /// The blue sheen's color: a deep blue with about 6% luminance.
    public static let blueTint: UInt32 = 0x163F94

    /// Opacity of white for secondary and tertiary text on the sheened cards and at night
    /// (0.82 and 0.66 in the mockup, which fall under 4.5:1 there).
    public static let brightInk2 = 0.92
    public static let brightInk3 = 0.82

    /// Relative luminance the sky behind the hero should not exceed (white is about 3.6:1).
    public static let heroTarget = 0.24

    /// Color of the sheen under the cards on this sky.
    public static func sheenTint(for condition: SkyCondition, isDaylight: Bool) -> UInt32 {
        tone(for: condition, isDaylight: isDaylight) == .blue ? blueTint : 0x000000
    }

    /// Opacity of the sheen under a card's content on this sky.
    public static func sheen(for condition: SkyCondition, isDaylight: Bool) -> Double {
        let gray = tone(for: condition, isDaylight: isDaylight) == .gray
        let before = cardBeforeSheen(condition: condition, isDaylight: isDaylight)
        let tint = ColorContrast.rgb(sheenTint(for: condition, isDaylight: isDaylight))
        let needed = opacity(of: tint, over: before, toReach: cardTarget)
        return min(max(needed, gray ? minimumSheen : 0), maximumSheen)
    }

    /// Estimated card color over the lightest (bottom) part of the sky, before the sheen.
    public static func cardBeforeSheen(condition: SkyCondition, isDaylight: Bool) -> ColorContrast.RGB {
        let bottom = ColorContrast.rgb(Palette.skyStops(for: condition, isDaylight: isDaylight).last ?? 0)
        let clouds = max(0, cloudStrength(for: condition, isDaylight: isDaylight) - cloudStrength(for: .cloudy, isDaylight: true))
        return ColorContrast.blend(ColorContrast.white, opacity: glassLift + cloudLift * clouds, over: bottom)
    }

    /// Estimated card color behind the text, sheen included.
    public static func card(condition: SkyCondition, isDaylight: Bool) -> ColorContrast.RGB {
        let tint = ColorContrast.rgb(sheenTint(for: condition, isDaylight: isDaylight))
        return ColorContrast.blend(tint, opacity: sheen(for: condition, isDaylight: isDaylight),
                                   over: cardBeforeSheen(condition: condition, isDaylight: isDaylight))
    }

    /// Estimated lightest sky behind the hero (just above the middle of the hero block, where the
    /// clouds drift), before the scrim.
    public static func heroBeforeScrim(condition: SkyCondition, isDaylight: Bool) -> ColorContrast.RGB {
        let stops = Palette.skyStops(for: condition, isDaylight: isDaylight).map(ColorContrast.rgb)
        let sky = ColorContrast.blend(stops[1], opacity: 0.56, over: stops[0])
        let clouds = 0.06 + 0.3 * cloudStrength(for: condition, isDaylight: isDaylight)
        return ColorContrast.blend(ColorContrast.white, opacity: clouds, over: sky)
    }

    /// Opacity of the soft scrim in the sky's top color behind the hero (0 where the hero already
    /// holds 3:1, which is every sky but the bright blue day ones).
    public static func heroScrim(for condition: SkyCondition, isDaylight: Bool) -> Double {
        let top = ColorContrast.rgb(Palette.skyStops(for: condition, isDaylight: isDaylight).first ?? 0)
        return opacity(of: top, over: heroBeforeScrim(condition: condition, isDaylight: isDaylight), toReach: heroTarget)
    }

    /// Estimated lightest sky behind the hero, scrim included.
    public static func hero(condition: SkyCondition, isDaylight: Bool) -> ColorContrast.RGB {
        let top = ColorContrast.rgb(Palette.skyStops(for: condition, isDaylight: isDaylight).first ?? 0)
        return ColorContrast.blend(top, opacity: heroScrim(for: condition, isDaylight: isDaylight),
                                   over: heroBeforeScrim(condition: condition, isDaylight: isDaylight))
    }

    /// The smallest opacity of `color` over `background` that brings it to `luminance` or below
    /// (1 if even the color alone is lighter).
    static func opacity(of color: ColorContrast.RGB, over background: ColorContrast.RGB, toReach luminance: Double) -> Double {
        guard ColorContrast.luminance(background) > luminance else { return 0 }
        var low = 0.0
        var high = 1.0
        for _ in 0..<32 {
            let mid = (low + high) / 2
            if ColorContrast.luminance(ColorContrast.blend(color, opacity: mid, over: background)) > luminance {
                low = mid
            } else {
                high = mid
            }
        }
        return high
    }
}
#endif
