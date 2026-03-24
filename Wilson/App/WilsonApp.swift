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
    }
}
