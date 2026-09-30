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
/// How Liquid's glass cards sit on the condition sky.
///
/// Blue skies (clear and partly cloudy, day or night) keep the light, clear glass of the mockup.
/// On gray skies (clouds, wind, fog, rain, snow, sleet, storms, overcast nights) clear glass lets
/// the pale sky through and white type washes out, so each card gets a dark sheen under its
/// content. The sheen is sized from the sky itself: enough to bring a card over the lightest part
/// of that sky down to ``cardTarget``, where white text is about 7:1 and the tertiary text
/// (white at 82%) stays above 4.5:1. Apple's guidance for the clear glass variant over bright
/// content is the same idea: a dimming layer under it.
public enum LiquidGlass {
    public enum Tone: Sendable {
        /// Light, clear glass with a white tint.
        case light
        /// Clear glass with a dark sheen under the content.
        case dark
    }

    public static func tone(for condition: SkyCondition, isDaylight: Bool) -> Tone {
        switch condition.family {
        case .clear, .partlyCloudy: return .light
        default: return .dark
        }
    }

    /// Relative luminance the card behind the text should not exceed.
    public static let cardTarget = 0.10

    /// How much lighter than the sky a card renders before the sheen: the glass highlight and
    /// the drifting clouds, as a share of the way to white (measured about +40 on a mid-gray
    /// sky, of which the white tint of the light glass was about +18).
    public static let glassLift = 0.24

    /// The sheen never drops below this, so dark skies still read as the gray-sky treatment.
    public static let minimumSheen = 0.2
    public static let maximumSheen = 0.6

    /// Opacity of white for secondary and tertiary text on a gray sky (0.82 and 0.66 on blue
    /// skies, as in the mockup).
    public static let graySkyInk2 = 0.92
    public static let graySkyInk3 = 0.82

    /// Opacity of the black sheen under a card's content on this sky (0 on blue skies).
    public static func sheen(for condition: SkyCondition, isDaylight: Bool) -> Double {
        guard tone(for: condition, isDaylight: isDaylight) == .dark else { return 0 }
        let card = cardBeforeSheen(condition: condition, isDaylight: isDaylight)
        let luminance = ColorContrast.luminance(card)
        guard luminance > cardTarget else { return minimumSheen }
        // Darkening by (1 - sheen) in sRGB scales luminance by about (1 - sheen)^2.2.
        let keep = pow(cardTarget / luminance, 1 / 2.2)
        return min(max(1 - keep, minimumSheen), maximumSheen)
    }

    /// Estimated card color over the lightest (bottom) part of the sky, before the sheen.
    public static func cardBeforeSheen(condition: SkyCondition, isDaylight: Bool) -> ColorContrast.RGB {
        let bottom = ColorContrast.rgb(Palette.skyStops(for: condition, isDaylight: isDaylight).last ?? 0)
        return ColorContrast.blend(ColorContrast.white, opacity: glassLift, over: bottom)
    }

    /// Estimated card color behind the text, sheen included.
    public static func card(condition: SkyCondition, isDaylight: Bool) -> ColorContrast.RGB {
        let before = cardBeforeSheen(condition: condition, isDaylight: isDaylight)
        return ColorContrast.blend(ColorContrast.black, opacity: sheen(for: condition, isDaylight: isDaylight), over: before)
    }
}
#endif
