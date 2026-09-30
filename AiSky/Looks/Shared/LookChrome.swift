import AiSkyKit
import SwiftUI

extension AppTab: CaseIterable, Identifiable {
    static var allCases: [AppTab] { [.forecast, .radar, .locations, .settings] }

    var id: Self { self }

    var title: String {
        switch self {
        case .forecast: return "Forecast"
        case .radar: return "Radar"
        case .locations: return "Places"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .forecast: return "cloud.sun"
        case .radar: return "dot.radiowaves.left.and.right"
        case .locations: return "list.bullet"
        case .settings: return "gearshape"
        }
    }
}

/// The selected look's bottom bar. Liquid keeps the system (Liquid Glass) tab bar instead.
struct LookTabBar: View {
    @Environment(\.lookTokens) private var t
    @Binding var selection: AppTab

    var body: some View {
        Group {
            switch t.look {
            case .obsidian: ObsidianTabBar(selection: $selection)
            case .editorial: EditorialTabBar(selection: $selection)
            case .horizon: HorizonTabBar(selection: $selection)
            case .chroma: ChromaTabBar(selection: $selection)
            case .instrument, .liquid: InstrumentTabBar(selection: $selection)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// A tab button: a real button with the selected trait and a spoken label.
private struct TabButton<LabelView: View>: View {
    let tab: AppTab
    @Binding var selection: AppTab
    @ViewBuilder let label: (Bool) -> LabelView

    var body: some View {
        let selected = tab == selection
        Button {
            selection = tab
        } label: {
            label(selected)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Four condensed caps tabs; the selected one cream under a 3 pt orange rule.
private struct InstrumentTabBar: View {
    @Environment(\.lookTokens) private var t
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                TabButton(tab: tab, selection: $selection) { selected in
                    Text(tab.title)
                        .lookLabel(t, size: 12, color: selected ? t.ink : t.ink3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 19)
                        .padding(.bottom, 14)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(selected ? t.now : Color.clear)
                                .frame(height: 3)
                                .offset(y: -1)
                        }
                }
            }
        }
        .padding(.horizontal, t.gutter)
        .background(alignment: .top) {
            t.background
                .overlay(alignment: .top) { Rectangle().fill(t.track).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// Mono caps spread edge to edge; the selected one underlined in white.
private struct ObsidianTabBar: View {
    @Environment(\.lookTokens) private var t
    @Binding var selection: AppTab

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                if index > 0 { Spacer(minLength: 8) }
                TabButton(tab: tab, selection: $selection) { selected in
                    Text(tab.title)
                        .lookLabel(t, size: 11, color: selected ? t.ink : t.ink3)
                        .lineLimit(1)
                        .padding(.top, 20)
                        .padding(.bottom, 9)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(selected ? t.ink : Color.clear).frame(height: 2)
                        }
                        .padding(.bottom, 8)
                }
            }
        }
        .padding(.horizontal, t.gutter)
        .background(alignment: .top) {
            t.background
                .overlay(alignment: .top) { Rectangle().fill(t.line).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// Small caps under an ink rule; the selected one underlined.
private struct EditorialTabBar: View {
    @Environment(\.lookTokens) private var t
    @Binding var selection: AppTab

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                if index > 0 { Spacer(minLength: 8) }
                TabButton(tab: tab, selection: $selection) { selected in
                    Text(tab.title)
                        .lookLabel(t, size: 11, color: selected ? t.ink : t.ink2)
                        .lineLimit(1)
                        .padding(.bottom, 5)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(selected ? t.ink : Color.clear).frame(height: 1.5)
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 14)
                }
            }
        }
        .padding(.horizontal, t.gutter)
        .background(alignment: .top) {
            t.background
                .overlay(alignment: .top) { Rectangle().fill(t.rule).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// Line icons with small labels; the forecast tab reads "Timeline".
private struct HorizonTabBar: View {
    @Environment(\.lookTokens) private var t
    @Binding var selection: AppTab

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                if index > 0 { Spacer(minLength: 8) }
                TabButton(tab: tab, selection: $selection) { selected in
                    VStack(spacing: 3) {
                        HorizonTabGlyph(tab: tab)
                            .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                            .frame(width: 22, height: 22)
                        Text(tab == .forecast ? "Timeline" : tab.title)
                            .font(t.font(.label, 10, relativeTo: .caption2))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selected ? t.ink : Palette.color(hex: 0x5D6A80))
                    .frame(minWidth: 52)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(.horizontal, 28)
        .background(alignment: .top) {
            t.background
                .overlay(alignment: .top) { Rectangle().fill(t.line).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// Horizon's tab glyphs, drawn from the mockup's 24-point line icons.
struct HorizonTabGlyph: Shape {
    let tab: AppTab

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        func line(_ path: inout Path, _ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
            path.move(to: p(x1, y1))
            path.addLine(to: p(x2, y2))
        }
        func circle(_ path: inout Path, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
            path.addEllipse(in: CGRect(x: rect.minX + (x - r) * s, y: rect.minY + (y - r) * s, width: 2 * r * s, height: 2 * r * s))
        }
        var path = Path()
        switch tab {
        case .forecast:
            line(&path, 5, 3, 5, 21)
            line(&path, 5, 7, 13, 7)
            line(&path, 5, 12, 17, 12)
            line(&path, 5, 17, 11, 17)
        case .radar:
            circle(&path, 12, 12, 9)
            circle(&path, 12, 12, 5)
            line(&path, 12, 12, 17, 7)
        case .locations:
            for y: CGFloat in [6, 12, 18] {
                line(&path, 8, y, 21, y)
                line(&path, 3.5, y, 3.51, y)
            }
        case .settings:
            line(&path, 4, 7, 14, 7)
            line(&path, 18, 7, 20, 7)
            line(&path, 4, 17, 8, 17)
            line(&path, 12, 17, 20, 17)
            circle(&path, 16, 7, 2)
            circle(&path, 10, 17, 2)
        }
        return path
    }
}

/// A navy pill floating over the cream page; the selected tab is a mustard pill.
private struct ChromaTabBar: View {
    @Environment(\.lookTokens) private var t
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                if index > 0 { Spacer(minLength: 2) }
                TabButton(tab: tab, selection: $selection) { selected in
                    Text(tab.title)
                        .font(t.font(.textStrong, 13, relativeTo: .footnote))
                        .lineLimit(1)
                        .foregroundStyle(selected ? ChromaPalette.navy : ChromaPalette.cream)
                        .padding(.vertical, 11)
                        .padding(.horizontal, selected ? 18 : 10)
                        .background(Capsule().fill(selected ? ChromaPalette.mustard : Color.clear))
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 60)
        .background(Capsule().fill(ChromaPalette.navy))
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(t.background.ignoresSafeArea(edges: .bottom))
    }
}

/// Page background: the condition sky for Liquid, the look's paper or ink elsewhere.
struct LookPageBackground: View {
    @Environment(\.lookTokens) private var t
    var condition: SkyCondition = .partlyCloudy
    var isDaylight = true

    var body: some View {
        if t.usesSky {
            ZStack {
                SkyBackground(condition: condition, isDaylight: isDaylight)
                LiquidClouds(condition: condition, isDaylight: isDaylight)
            }
        } else {
            t.background
        }
    }
}

/// Which forecast page is visible: dots (with an arrow for the device location) or short ticks.
struct LookPageIndicator: View {
    @Environment(\.lookTokens) private var t
    let locations: [WeatherLocation]
    let selectedID: String

    var body: some View {
        let ticks = t.look == .instrument || t.look == .obsidian || t.look == .editorial
        HStack(spacing: ticks ? 4 : 6) {
            ForEach(locations) { location in
                let selected = location.id == selectedID
                if ticks {
                    Capsule()
                        .fill(selected ? t.ink : t.ink3.opacity(0.6))
                        .frame(width: selected ? 12 : 6, height: 2)
                } else if location.isCurrentLocation {
                    Image(systemName: "location.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(t.ink.opacity(selected ? 1 : 0.4))
                } else {
                    Circle()
                        .fill(t.ink.opacity(selected ? 1 : 0.35))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(t.look == .liquid ? Color.black.opacity(0.15) : Color.clear, in: Capsule())
        .animation(.easeInOut(duration: 0.2), value: selectedID)
        .accessibilityElement()
        .accessibilityLabel(pageLabel)
    }

    private var pageLabel: String {
        let index = (locations.firstIndex { $0.id == selectedID } ?? 0) + 1
        return "Page \(index) of \(locations.count)"
    }
}

extension View {
    /// A screen in the look: its page background, ink and color scheme.
    func lookScreen(_ tokens: LookTokens) -> some View {
        background(LookPageBackground().ignoresSafeArea())
            .foregroundStyle(tokens.ink)
    }

    /// Lists and forms in the look: no system grouped background, the look's page instead.
    func lookList(_ tokens: LookTokens) -> some View {
        scrollContentBackground(tokens.look == .liquid ? .visible : .hidden)
            .background(tokens.look == .liquid ? AnyView(Color.clear) : AnyView(tokens.background.ignoresSafeArea()))
    }

    /// Row fill for lists and forms in the look.
    func lookRow(_ tokens: LookTokens) -> some View {
        listRowBackground(rowFill(tokens))
            .listRowSeparatorTint(tokens.line)
    }
}

private func rowFill(_ tokens: LookTokens) -> Color? {
    switch tokens.look {
    case .liquid: return nil
    case .obsidian, .editorial: return tokens.background
    case .instrument, .horizon: return tokens.surface
    case .chroma: return tokens.surface
    }
}

/// A large screen title in the look's voice (Places, Settings) for looks that hide the system
/// navigation title.
struct LookScreenTitle: View {
    @Environment(\.lookTokens) private var t
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch t.look {
            case .instrument:
                Text(title).lookLabel(t, size: 15, color: t.ink)
            case .obsidian:
                Text(title + ".")
                    .font(t.font(.numberLight, 34, relativeTo: .largeTitle))
                    .tracking(-0.8)
            case .editorial:
                Text(title)
                    .font(t.font(.headline, 36, relativeTo: .largeTitle))
                    .tracking(-0.6)
            case .horizon:
                Text(title).font(t.font(.headline, 28, relativeTo: .largeTitle))
            case .chroma:
                Text(title)
                    .font(t.font(.display, 40, relativeTo: .largeTitle))
                    .tracking(-1.2)
            case .liquid:
                Text(title).font(.largeTitle.bold())
            }
            if let subtitle {
                Text(subtitle)
                    .lookLabel(t, color: t.ink2)
            }
            if t.look == .editorial {
                LookRule(strong: true).padding(.top, 6)
            }
        }
        .foregroundStyle(t.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Inline navigation title set in the look's type (the system title for Liquid).
    func lookNavigationTitle(_ title: String) -> some View {
        modifier(LookNavigationTitle(title: title))
    }
}

private struct LookNavigationTitle: ViewModifier {
    @Environment(\.lookTokens) private var t
    let title: String

    func body(content: Content) -> some View {
        if t.look == .liquid {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        titleText
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                .toolbarBackground(t.background, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var titleText: some View {
        switch t.look {
        case .instrument:
            Text(title).lookLabel(t, size: 14, color: t.ink, tracking: 3)
        case .obsidian:
            Text(title).lookLabel(t, size: 12, color: t.ink, tracking: 2)
        case .editorial:
            Text(title).font(t.font(.headline, 19)).foregroundStyle(t.ink)
        case .horizon, .chroma, .liquid:
            Text(title).font(t.font(.headline, 17)).foregroundStyle(t.ink)
        }
    }
}

extension View {
    /// An overlay panel on the radar map in the look's surface: glass, a flat card, a ruled box
    /// or a cream block.
    func lookPanel(_ tokens: LookTokens, radius: CGFloat = 16) -> some View {
        modifier(LookPanel(tokens: tokens, radius: radius))
    }
}

private struct LookPanel: ViewModifier {
    let tokens: LookTokens
    let radius: CGFloat

    func body(content: Content) -> some View {
        let square = tokens.surfaceStyle == .hairline
        let shape = RoundedRectangle(cornerRadius: square ? 0 : radius, style: .continuous)
        switch tokens.look {
        case .liquid:
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular, in: shape)
            } else {
                content.background(.regularMaterial, in: shape)
            }
        case .obsidian, .editorial:
            content
                .background(shape.fill(tokens.background.opacity(0.94)))
                .overlay(shape.strokeBorder(tokens.look == .editorial ? tokens.rule : tokens.line, lineWidth: 1))
        case .instrument, .horizon:
            content
                .background(shape.fill(tokens.surface.opacity(0.96)))
                .overlay(shape.strokeBorder(tokens.line, lineWidth: 1))
        case .chroma:
            content.background(shape.fill(tokens.background))
        }
    }
}
