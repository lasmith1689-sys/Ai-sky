import AiSkyKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let look = model.look
        let tokens = LookTokens.tokens(for: look)
        ZStack {
            LookedRoot(look: look)
                .id(look)
                .transition(.opacity)
        }
        .environment(\.lookTokens, tokens)
        .preferredColorScheme(tokens.colorScheme)
        .tint(tokens.accent)
        // Switching looks crossfades (instantly under Reduce Motion).
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: look)
        .onChange(of: model.settings) { oldValue, newValue in
            model.settingsChanged(from: oldValue, to: newValue)
        }
        .task {
            await model.start()
        }
    }
}

/// The tabs in one look. Liquid keeps the system Liquid Glass tab bar; the other looks keep
/// `TabView` for each tab's state but draw their own bar.
private struct LookedRoot: View {
    @Environment(AppModel.self) private var model
    @Environment(\.lookTokens) private var t
    let look: Look

    var body: some View {
        @Bindable var model = model
        if look == .liquid {
            TabView(selection: $model.selectedTab) {
                ForEach(AppTab.allCases) { tab in
                    tabContent(tab)
                        .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                        .tag(tab)
                }
            }
        } else {
            VStack(spacing: 0) {
                TabView(selection: $model.selectedTab) {
                    ForEach(AppTab.allCases) { tab in
                        tabContent(tab)
                            .toolbar(.hidden, for: .tabBar)
                            .tag(tab)
                    }
                }
                LookTabBar(selection: $model.selectedTab)
            }
            .background(t.background.ignoresSafeArea())
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: AppTab) -> some View {
        switch tab {
        case .forecast: ForecastTab()
        case .radar: RadarTab()
        case .locations: LocationsTab()
        case .settings: SettingsTab()
        }
    }
}
