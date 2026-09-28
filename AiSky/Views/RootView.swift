import AiSkyKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            ForecastTab()
                .tabItem { Label("Forecast", systemImage: "cloud.sun.fill") }
                .tag(AppTab.forecast)
            RadarTab()
                .tabItem { Label("Radar", systemImage: "dot.radiowaves.left.and.right") }
                .tag(AppTab.radar)
            LocationsTab()
                .tabItem { Label("Locations", systemImage: "list.bullet") }
                .tag(AppTab.locations)
            SettingsTab()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .onChange(of: model.settings) { oldValue, newValue in
            model.settingsChanged(from: oldValue, to: newValue)
        }
        .task {
            await model.start()
        }
    }
}
