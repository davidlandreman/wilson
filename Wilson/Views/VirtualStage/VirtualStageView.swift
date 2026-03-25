import SwiftUI

struct VirtualStageView: View {
    @Environment(\.appState) private var appState

    private var virtualFixtures: [StageFixture] {
        appState.fixtureManager.fixtures.filter(\.isVirtual)
    }

    var body: some View {
        if virtualFixtures.isEmpty {
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
        }
    }
}
