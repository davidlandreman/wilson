import SwiftData
import SwiftUI

@main
struct WilsonApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.appState, appState)
        }
        .defaultSize(width: 1200, height: 800)
        .modelContainer(for: [
            DMXScene.self,
            FixtureProfile.self,
            PatchedFixture.self,
            Cue.self,
            ColorPalette.self,
        ])

        Window("Virtual Stage", id: "virtual-stage-fullscreen") {
            FullScreenStageView()
                .environment(\.appState, appState)
        }
        .defaultSize(width: 1920, height: 1080)
    }
}
