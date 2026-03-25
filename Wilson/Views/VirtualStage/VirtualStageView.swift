import SwiftUI

struct VirtualStageView: View {
    @Environment(\.appState) private var appState

    private var virtualFixtures: [StageFixture] {
        appState.fixtureManager.fixtures.filter(\.isVirtual)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if virtualFixtures.isEmpty {
                    Text("Add virtual fixtures in Light Designer")
                        .foregroundStyle(.gray)
                } else {
                    ForEach(virtualFixtures) { fixture in
                        let renderState = appState.virtualOutput.renderStates[fixture.id]
                        VirtualFixtureView(
                            label: fixture.label,
                            color: renderState?.color ?? .white,
                            intensity: renderState?.intensity ?? 0
                        )
                        .position(
                            x: fixture.position.x * geometry.size.width,
                            y: fixture.position.y * geometry.size.height
                        )
                    }
                }
            }
        }
    }
}
