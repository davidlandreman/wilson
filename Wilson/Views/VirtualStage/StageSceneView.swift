import SceneKit
import SwiftUI

/// NSViewRepresentable bridging the 3D SceneKit stage into SwiftUI.
struct StageSceneView: NSViewRepresentable {
    let fixtures: [StageFixture]
    let renderStates: [UUID: VirtualFixtureRenderState]

    func makeCoordinator() -> StageSceneCoordinator {
        StageSceneCoordinator()
    }

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero)
        scnView.scene = context.coordinator.scene
        scnView.pointOfView = context.coordinator.cameraNode
        scnView.backgroundColor = .black
        scnView.antialiasingMode = .multisampling4X
        scnView.preferredFramesPerSecond = 60
        scnView.rendersContinuously = true
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        return scnView
    }

    func updateNSView(_ scnView: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.syncFixtures(fixtures)
        coordinator.updateLighting(renderStates)
    }
}
