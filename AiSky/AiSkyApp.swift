import AiSkyKit
import os
import SwiftUI

@main
struct AiSkyApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        // A wrong PostScript name or UIAppFonts entry silently falls back to the system font and
        // undoes a look; the CI smoke test reads this line from the log and fails on "missing".
        let logger = Logger(subsystem: "com.lasmith1689.AiSky", category: "Fonts")
        let missing = LookFonts.missing()
        if missing.isEmpty {
            logger.notice("Look fonts: all \(LookFonts.all.count, privacy: .public) loaded")
        } else {
            logger.error("Look fonts missing: \(missing.joined(separator: ", "), privacy: .public)")
        }
        #endif
    }

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
