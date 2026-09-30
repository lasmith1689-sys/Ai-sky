import AiSkyKit
import SwiftUI

// Building blocks every look shares. Each reads the selected look's tokens from the environment
// and draws itself in that look's surface style: Liquid Glass, flat bordered cards, hairline
// rules or color blocks.

/// A section of the forecast or a sheet.
struct WeatherCard<Content: View>: View {
    @Environment(\.lookTokens) private var t
    let title: String
    var systemImage: String?
    var accessory: String?
    var tone: LookTokens.Tone = .standard
    @ViewBuilder let content: () -> Content

    init(
        title: String, systemImage: String? = nil, accessory: String? = nil, tone: LookTokens.Tone = .standard,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory
        self.tone = tone
        self.content = content
    }

    var body: some View {
        let tokens = t.toned(tone)
        VStack(alignment: .leading, spacing: tokens.surfaceStyle == .hairline ? 12 : 10) {
            CardHeader(title: title, systemImage: systemImage, accessory: accessory)
            content()
        }
        .padding(.horizontal, tokens.cardPadding)
        .padding(.vertical, tokens.surfaceStyle == .hairline ? 0 : tokens.cardPadding - 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lookSurface(tokens, radius: tokens.cardRadius)
        .foregroundStyle(tokens.ink)
        .environment(\.lookTokens, tokens)
    }
}

/// Title row of a card in the look's voice.
struct CardHeader: View {
    @Environment(\.lookTokens) private var t
    let title: String
    var systemImage: String?
    var accessory: String?

    var body: some View {
        switch t.surfaceStyle {
        case .glass:
            HStack {
                if let systemImage {
                    Label(title.uppercased(), systemImage: systemImage)
                } else {
                    Text(title.uppercased())
                }
                Spacer(minLength: 8)
                if let accessory {
                    Text(accessory)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(t.ink3)
            .accessibilityAddTraits(.isHeader)
        case .block:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(t.font(.textStrong, 18))
                    .foregroundStyle(t.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let accessory {
                    Text(accessory)
                        .lookLabel(t, size: 11, color: t.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        case .flat, .hairline:
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .lookLabel(t)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    if let accessory {
                        Text(accessory)
                            .lookLabel(t, size: t.labelSize - (t.look == .instrument ? 1 : 0), color: t.ink3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                if t.surfaceStyle == .hairline {
                    LookRule(strong: true)
                }
            }
        }
    }
}

/// A 1 pt rule in the look's line color (or its strong rule color).
struct LookRule: View {
    @Environment(\.lookTokens) private var t
    var strong = false

    var body: some View {
        Rectangle()
            .fill(strong ? t.rule : t.line)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// Tile for the details grid (humidity, wind, UV...).
struct DetailTile<Accessory: View>: View {
    @Environment(\.lookTokens) private var t
    let title: String
    let systemImage: String
    let value: String
    var detail: String?
    var tone: LookTokens.Tone = .standard
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        let tokens = t.toned(tone)
        let hairline = tokens.surfaceStyle == .hairline
        VStack(alignment: .leading, spacing: 8) {
            if hairline {
                LookRule()
                    .padding(.bottom, 4)
            }
            titleView(tokens)
            Text(value)
                .font(valueFont(tokens))
                .foregroundStyle(tokens.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            accessory()
            Spacer(minLength: 0)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(tokens.font(.text, tokens.bodySize - 2))
                    .foregroundStyle(tokens.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(hairline ? 0 : 14)
        .padding(.bottom, hairline ? 12 : 0)
        .frame(maxWidth: .infinity, minHeight: hairline ? 130 : 156, alignment: .topLeading)
        .lookSurface(tokens, radius: tokens.tileRadius)
        .foregroundStyle(tokens.ink)
        .environment(\.lookTokens, tokens)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func titleView(_ tokens: LookTokens) -> some View {
        if tokens.surfaceStyle == .glass {
            Label(title.uppercased(), systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tokens.ink3)
                .lineLimit(1)
        } else {
            Text(title)
                .lookLabel(tokens, size: tokens.look == .instrument ? 11 : nil, color: tokens.ink2)
                .lineLimit(1)
        }
    }

    private func valueFont(_ tokens: LookTokens) -> Font {
        switch tokens.look {
        case .liquid: return .title.weight(.medium)
        case .obsidian: return tokens.font(.numberLight, 28)
        case .instrument: return tokens.font(.numberLight, 28)
        case .editorial: return tokens.font(.numberLight, 34)
        case .horizon: return tokens.font(.numberLight, 30)
        case .chroma: return tokens.font(.textStrong, 28)
        }
    }
}

extension DetailTile where Accessory == EmptyView {
    init(title: String, systemImage: String, value: String, detail: String? = nil, tone: LookTokens.Tone = .standard) {
        self.init(title: title, systemImage: systemImage, value: value, detail: detail, tone: tone) { EmptyView() }
    }
}

/// Horizontal category scale with a marker, used for AQI and UV.
struct ScaleBar: View {
    @Environment(\.lookTokens) private var t
    let colors: [Color]
    /// 0...1 position of the marker.
    let position: Double

    var body: some View {
        if t.look == .liquid {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    Circle()
                        .fill(.white)
                        .overlay(Circle().stroke(.black.opacity(0.4), lineWidth: 1))
                        .frame(width: 9, height: 9)
                        .offset(x: max(0, min(proxy.size.width - 9, proxy.size.width * position - 4.5)))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        } else {
            ScaleTrack(fraction: position, fill: t.ink2, track: t.track, marker: t.ink, colors: colors.map { $0.opacity(t.colorScheme == .light ? 0.9 : 0.75) })
        }
    }
}

/// A tappable row at the bottom of a card that opens another screen ("Time Machine  >").
struct CardLinkRow: View {
    @Environment(\.lookTokens) private var t
    let title: String
    let systemImage: String
    var detail: String?

    var body: some View {
        HStack(spacing: 10) {
            if t.look == .liquid {
                Label(title, systemImage: systemImage)
                    .font(.body.weight(.semibold))
            } else if t.surfaceStyle == .block {
                Text(title)
                    .font(t.font(.textStrong, 16))
            } else {
                Text(title)
                    .lookLabel(t, size: t.labelSize + 1, color: t.ink)
            }
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(t.look == .liquid ? .caption : t.font(.text, t.bodySize - 2))
                    .foregroundStyle(t.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(t.ink3)
        }
        .padding(.top, 4)
        .padding(.vertical, t.surfaceStyle == .hairline ? 4 : 0)
        .contentShape(Rectangle())
    }
}

/// Selector for chart metrics and periods, drawn in the look's style: capsules, underlined text
/// tabs or pills.
struct LookChips<Option: Hashable & Identifiable>: View {
    @Environment(\.lookTokens) private var t
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(options) { option in
                    let selected = option == selection
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selection = option }
                    } label: {
                        chip(title(option), selected: selected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 1)
            .background(alignment: .bottom) {
                if underlined {
                    Rectangle().fill(t.line).frame(height: 1)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var underlined: Bool {
        t.look == .instrument || t.look == .obsidian || t.look == .editorial
    }

    private var spacing: CGFloat { underlined ? 18 : 6 }

    @ViewBuilder
    private func chip(_ text: String, selected: Bool) -> some View {
        switch t.look {
        case .liquid:
            Text(text)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Color.white.opacity(0.9) : Color.white.opacity(0.14), in: Capsule())
                .foregroundStyle(selected ? Color.black : Color.white)
        case .instrument, .obsidian, .editorial:
            Text(text)
                .lookLabel(t, size: t.look == .instrument ? 12 : t.labelSize + 0.5, color: selected ? t.ink : t.ink3)
                .lineLimit(1)
                .padding(.top, 6)
                .padding(.bottom, 9)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(selected ? (t.look == .instrument ? t.now : t.ink) : Color.clear)
                        .frame(height: t.look == .instrument ? 2 : 1.5)
                }
                .contentShape(Rectangle())
        case .horizon:
            Text(text)
                .font(t.font(.textStrong, 12))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? t.ink : t.surfaceAlt, in: Capsule())
                .foregroundStyle(selected ? t.background : t.ink2)
        case .chroma:
            Text(text)
                .font(t.font(.textStrong, 13))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? ChromaPalette.mustard : t.surfaceAlt.opacity(0.6), in: Capsule())
                .foregroundStyle(ChromaPalette.navy)
        }
    }
}

/// Buttons in the look's style.
struct LookButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    var kind: Kind = .secondary
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        LookButtonBody(configuration: configuration, kind: kind, fullWidth: fullWidth)
    }

    private struct LookButtonBody: View {
        @Environment(\.lookTokens) private var t
        @Environment(\.isEnabled) private var isEnabled
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        let fullWidth: Bool

        var body: some View {
            let radius: CGFloat = t.surfaceStyle == .hairline ? 0 : (t.look == .liquid || t.look == .chroma ? 999 : t.tileRadius)
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            let primary = kind == .primary
            label
                .lineLimit(1)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.vertical, 13)
                .padding(.horizontal, 18)
                .foregroundStyle(primary ? t.onAccent : t.ink)
                .background(shape.fill(primary ? t.accent : (t.look == .liquid ? Color.white.opacity(0.16) : t.surface)))
                .overlay(shape.strokeBorder(primary ? Color.clear : (t.surfaceStyle == .hairline ? t.rule : t.line), lineWidth: 1))
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
                .contentShape(shape)
        }

        @ViewBuilder
        private var label: some View {
            switch t.look {
            case .liquid, .horizon, .chroma:
                configuration.label.font(t.font(.textStrong, 16))
            case .instrument, .obsidian, .editorial:
                configuration.label.lookLabel(t, size: 13, color: kind == .primary ? t.onAccent : t.ink)
            }
        }
    }
}

extension View {
    /// Background and border of a card in the look's surface style.
    func lookSurface(_ tokens: LookTokens, radius: CGFloat) -> some View {
        modifier(LookSurfaceModifier(tokens: tokens, radius: radius))
    }
}

struct LookSurfaceModifier: ViewModifier {
    let tokens: LookTokens
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch tokens.surfaceStyle {
        case .glass:
            // Light, clear glass with a bright hairline, as in the mockup (regular glass turns dark
            // under the dark color scheme the sky pages use).
            if #available(iOS 26.0, *) {
                content
                    .glassEffect(.clear.tint(Color.white.opacity(0.16)), in: shape)
                    .overlay(shape.strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
            } else {
                content
                    .background(.ultraThinMaterial.opacity(0.7), in: shape)
                    .background(Color.white.opacity(0.12), in: shape)
                    .overlay(shape.strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
            }
        case .flat:
            content
                .background(shape.fill(tokens.surface))
                .overlay(shape.strokeBorder(tokens.line, lineWidth: 1))
        case .hairline:
            content
        case .block:
            content.background(shape.fill(tokens.surface))
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self = Palette.color(hex: hex)
    }
}
