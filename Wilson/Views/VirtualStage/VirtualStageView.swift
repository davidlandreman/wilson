import SwiftUI

struct VirtualStageView: View {
    @Environment(\.appState) private var appState
    @Environment(\.openWindow) private var openWindow

    private var virtualFixtures: [StageFixture] {
        appState.fixtureManager.fixtures.filter(\.isVirtual)
    }

    var body: some View {
        Group {
            if appState.isStageWindowOpen {
                Color.black
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "macwindow.on.rectangle")
                                .font(.largeTitle)
                                .foregroundStyle(.gray)
                            Text("Virtual Stage is open in a separate window")
                                .foregroundStyle(.gray)
                        }
                    }
            } else if virtualFixtures.isEmpty {
                Color.black
                    .overlay {
                        Text("Add virtual fixtures in Light Designer")
                            .foregroundStyle(.gray)
                    }
            } else {
                StageSceneView(
                    fixtures: virtualFixtures,
                    renderStates: appState.virtualOutput.renderStates
                )
                .overlay(alignment: .bottomLeading) {
                    EngineDebugOverlay()
                        .padding(8)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openWindow(id: "virtual-stage-fullscreen")
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .help("Open Full Screen Stage")
            }
        }
    }
}

struct FullScreenStageView: View {
    @Environment(\.appState) private var appState

    private var virtualFixtures: [StageFixture] {
        appState.fixtureManager.fixtures.filter(\.isVirtual)
    }

    var body: some View {
        StageSceneView(
            fixtures: virtualFixtures,
            renderStates: appState.virtualOutput.renderStates
        )
        .overlay(alignment: .bottomLeading) {
            EngineDebugOverlay()
                .padding(12)
        }
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .onAppear { appState.isStageWindowOpen = true }
        .onDisappear { appState.isStageWindowOpen = false }
    }
}
