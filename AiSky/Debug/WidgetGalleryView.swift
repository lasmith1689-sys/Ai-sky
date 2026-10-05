#if DEBUG
import AiSkyKit
import SwiftUI
import WidgetKit

/// Debug builds only: every widget family rendered inside the app from the widget extension's own
/// views (the shared `WidgetViews` folder), so the CI smoke test can photograph them per look.
/// `-AiSkyScreen widgets` shows page 1 (small, medium and Lock Screen), `widgets2` page 2 (large
/// conditions, rainfall) and `widgets3` page 3 (places, small rainfall, more Lock Screen). `-AiSkyWidgetMode tinted` renders them in the tinted (accented) rendering
/// mode on a dark plate with an amber tint: an approximation of the Tinted Home Screen, since
/// only the system applies the real one.
struct WidgetGalleryView: View {
    @Environment(AppModel.self) private var model
    let page: Int
    let tinted: Bool

    private let small: CGFloat = 170
    private let wide: CGFloat = 364

    var body: some View {
        let entry = self.entry
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Widgets · \(entry.settings.look.displayName) · \(tinted ? "Tinted (approximation)" : "Full color")")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                if page == 1 {
                    HStack(spacing: 12) {
                        tile("Conditions", .systemSmall, width: small, height: small) { ConditionsWidgetView(entry: entry) }
                        tile("Next Hour", .systemSmall, width: small, height: small) { NextHourWidgetView(entry: entry) }
                    }
                    tile("Conditions", .systemMedium, width: wide, height: small) { ConditionsWidgetView(entry: entry) }
                    tile("Next Hour", .systemMedium, width: wide, height: small) { NextHourWidgetView(entry: entry) }
                    HStack(alignment: .top, spacing: 12) {
                        tile("Air Quality", .systemSmall, width: small, height: small) { AirQualityWidgetView(entry: entry) }
                        VStack(alignment: .leading, spacing: 10) {
                            tile("Lock Screen", .accessoryRectangular, width: small, height: 72) { ConditionsWidgetView(entry: entry) }
                            HStack(spacing: 12) {
                                tile("Circular", .accessoryCircular, width: 72, height: 72) { ConditionsWidgetView(entry: entry) }
                                tile("AQI", .accessoryCircular, width: 72, height: 72) { AirQualityWidgetView(entry: entry) }
                            }
                        }
                    }
                } else if page == 2 {
                    tile("Conditions", .systemLarge, width: wide, height: 382) { ConditionsWidgetView(entry: entry) }
                    tile("Rainfall", .systemMedium, width: wide, height: small) { PrecipitationWidgetView(entry: entry) }
                } else {
                    tile("My Places", .systemLarge, width: wide, height: 382) { LocationsWidgetView(entry: places) }
                    HStack(alignment: .top, spacing: 12) {
                        tile("Rainfall", .systemSmall, width: small, height: small) { PrecipitationWidgetView(entry: entry) }
                        VStack(alignment: .leading, spacing: 10) {
                            tile("Rainfall", .accessoryRectangular, width: small, height: 72) { PrecipitationWidgetView(entry: entry) }
                            tile("Next Hour", .accessoryRectangular, width: small, height: 72) { NextHourWidgetView(entry: entry) }
                        }
                    }
                }
            }
            .padding(.horizontal, 19)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .background(Palette.color(hex: tinted ? 0x16130E : 0x3B4452).ignoresSafeArea())
    }

    /// Sample weather in the look on screen.
    private var entry: WeatherEntry {
        WeatherEntry(date: Date(), location: SampleData.location, snapshot: WeatherStore.demoSnapshot(for: SampleData.location),
                     settings: settings, errorMessage: nil)
    }

    private var places: LocationsEntry { .preview(settings: settings) }

    private var settings: AppSettings {
        var settings = model.settings
        settings.look = model.look
        return settings
    }

    /// One widget at its iPhone size, with the container background and content margins the
    /// system would add, and a caption under it.
    private func tile<Content: View>(
        _ title: String, _ family: WidgetFamily, width: CGFloat, height: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let mode: WidgetRenderingMode = family.isAccessory ? .vibrant : (tinted ? .accented : .fullColor)
        let tokens = entry.tokens
        let shape = RoundedRectangle(cornerRadius: family.isAccessory ? 14 : 22, style: .continuous)
        return VStack(alignment: .leading, spacing: 3) {
            content()
                .padding(family.isAccessory ? 4 : 16)
                .frame(width: width, height: height)
                .background {
                    if mode == .fullColor {
                        LookWidgetBackground(tokens: tokens, condition: entry.conditions?.condition ?? .partlyCloudy,
                                             isDaylight: entry.conditions?.isDaylight ?? true)
                    } else {
                        Palette.color(hex: family.isAccessory ? 0x222A36 : 0x3A3226)
                    }
                }
                .clipShape(shape)
                .environment(\.widgetLayoutFamily, family)
                .environment(\.widgetInkMode, mode)
                .environment(\.colorScheme, mode == .fullColor ? tokens.colorScheme : .dark)
                .colorMultiply(mode == .accented ? Palette.color(hex: 0xFFD9A0) : .white)
            Text("\(title) · \(caption(family))")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    private func caption(_ family: WidgetFamily) -> String {
        switch family {
        case .systemSmall: return "small"
        case .systemMedium: return "medium"
        case .systemLarge: return "large"
        case .accessoryRectangular: return "rectangular"
        case .accessoryCircular: return "circular"
        default: return "inline"
        }
    }
}
#endif
