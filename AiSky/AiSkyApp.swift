import AiSkyKit
import SwiftUI

@main
struct AiSkyApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { model.handle(url: $0) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.appDidBecomeActive()
            case .background:
                BackgroundRefresher.schedule()
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresher.taskIdentifier)) {
            await BackgroundRefresher.run()
        }
    }
}
