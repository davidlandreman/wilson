import os.log
import SwiftData
import SwiftUI

private let logger = Logger(subsystem: "Wilson", category: "App")

@main
struct WilsonApp: App {
    @State private var appState = AppState()
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            DMXScene.self,
            FixtureProfile.self,
            PatchedFixture.self,
            Cue.self,
            ColorPalette.self,
        ])
        do {
            modelContainer = try ModelContainer(for: schema)
        } catch {
            logger.warning("SwiftData migration failed, recreating store: \(error)")
            let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
            for ext in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: storeURL.path() + ext)
            }
            modelContainer = try! ModelContainer(for: schema)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.appState, appState)
        }
        .defaultSize(width: 1200, height: 800)
        .modelContainer(modelContainer)

        Window("Virtual Stage", id: "virtual-stage-fullscreen") {
            FullScreenStageView()
                .environment(\.appState, appState)
        }
        .defaultSize(width: 1920, height: 1080)
    }
}
