import SceneKit

/// Owns the SceneKit scene graph for the 3D virtual stage.
/// Bridges @Observable render states to SceneKit node properties.
@MainActor
final class StageSceneCoordinator {
    let scene: SCNScene
    let cameraNode: SCNNode
    private var fixtureLookup: [UUID: FixtureSceneNodes] = [:]
    private var currentFixtureIDs: [UUID] = []

    init() {
        scene = SCNScene()
        cameraNode = StageGeometry.makeCamera()
        configureFog()
        buildStaticScene()
    }

    // MARK: - Static Scene Setup

    private func configureFog() {
        scene.fogStartDistance = 5.0
        scene.fogEndDistance = 25.0
        scene.fogDensityExponent = 1.0
        scene.fogColor = NSColor(red: 0.005, green: 0.005, blue: 0.01, alpha: 1)
        scene.background.contents = NSColor.black
    }

    private func buildStaticScene() {
        let root = scene.rootNode
        root.addChildNode(StageGeometry.makeFloor())
        root.addChildNode(StageGeometry.makeBackWall())
        root.addChildNode(StageGeometry.makeTruss())
        root.addChildNode(cameraNode)
        root.addChildNode(StageGeometry.makeAmbientLight())
        root.addChildNode(StageGeometry.makeFillLight())
    }

    // MARK: - Fixture Sync (add/remove/reposition)

    func syncFixtures(_ fixtures: [StageFixture]) {
        let incoming = fixtures.map(\.id)

        // Quick check: if IDs haven't changed, skip rebuild
        if incoming == currentFixtureIDs { return }
        currentFixtureIDs = incoming

        let incomingSet = Set(incoming)
        let existingSet = Set(fixtureLookup.keys)

        // Remove fixtures no longer present
        for id in existingSet.subtracting(incomingSet) {
            if let nodes = fixtureLookup.removeValue(forKey: id) {
                nodes.containerNode.removeFromParentNode()
            }
        }

        // Add new fixtures
        for fixture in fixtures where !existingSet.contains(fixture.id) {
            let nodes = buildFixtureNodes(for: fixture)
            scene.rootNode.addChildNode(nodes.containerNode)
            fixtureLookup[fixture.id] = nodes
        }

        // Reposition all fixtures using center-out algorithm
        let total = fixtures.count
        for fixture in fixtures {
            guard let nodes = fixtureLookup[fixture.id] else { continue }
            let x = trussXPosition(slotIndex: fixture.trussSlot, totalFixtures: total)
            nodes.containerNode.position = SCNVector3(
                x,
                StageGeometry.trussHeight - StageGeometry.trussSection / 2,
                StageGeometry.trussDepth
            )
        }
    }

    // MARK: - Lighting Updates (hot path, ~60fps)

    func updateLighting(_ renderStates: [UUID: VirtualFixtureRenderState]) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0

        for (id, nodes) in fixtureLookup {
            guard let state = renderStates[id] else {
                // Fixture has no state — turn off
                nodes.spotLight.intensity = 0
                nodes.glowLight.intensity = 0
                nodes.beamMaterial.diffuse.contents = NSColor.black
                continue
            }

            let nsColor = state.nsColor
            let intensity = state.intensity

            // Update spot light
            nodes.spotLight.color = nsColor
            nodes.spotLight.intensity = CGFloat(intensity * 30000)

            // Update glow light — illuminates truss and fixture body
            nodes.glowLight.color = nsColor
            nodes.glowLight.intensity = CGFloat(intensity * 2000)

            // Update beam — brightness via dim color (not transparency).
            // Single-sided cone: ~8 overlapping faces from side.
            let beamBrightness = CGFloat(intensity * 0.35)
            let beamColor = NSColor(
                red: nsColor.redComponent * beamBrightness,
                green: nsColor.greenComponent * beamBrightness,
                blue: nsColor.blueComponent * beamBrightness,
                alpha: 1.0
            )
            nodes.beamMaterial.diffuse.contents = beamColor

            // Update pan — rotates the container around Y axis
            // 0.0 = full left, 0.5 = center (default), 1.0 = full right
            let panAngle = (state.pan - 0.5) * 2.0 * .pi // ±π range
            nodes.containerNode.eulerAngles.y = CGFloat(panAngle)

            // Update tilt — rotates the gimbal node (body + spot + beam as a unit)
            // 0.0 = straight down, 0.25 = 45° outward, 0.5 = horizontal
            nodes.gimbalNode.eulerAngles.x = CGFloat(state.tilt * .pi)
        }

        SCNTransaction.commit()
    }

    // MARK: - Fixture Node Construction

    private func buildFixtureNodes(for fixture: StageFixture) -> FixtureSceneNodes {
        let container = SCNNode()
        container.name = "fixture_\(fixture.id.uuidString)"

        // Yoke (hangs from truss — stays fixed, does not tilt)
        let (bodyNode, yokeNode) = StageGeometry.makeParCan()
        yokeNode.position = SCNVector3(0, -0.05, 0)
        container.addChildNode(yokeNode)

        // Gimbal node — rotates body, spot light, and beam as a unit for tilt
        let gimbalNode = SCNNode()
        gimbalNode.name = "gimbal"
        gimbalNode.position = SCNVector3(0, -0.18, 0) // pivot at fixture center
        container.addChildNode(gimbalNode)

        // Body (inside gimbal)
        bodyNode.position = SCNVector3(0, 0, 0)
        gimbalNode.addChildNode(bodyNode)

        // Spot light (inside gimbal, offset down from body)
        let (spotLightNode, spotLight) = StageGeometry.makeSpotLight()
        spotLightNode.position = SCNVector3(0, -0.14, 0)
        gimbalNode.addChildNode(spotLightNode)

        // Beam cone (inside gimbal, same position as spot)
        let (beamConeNode, beamMaterial) = StageGeometry.makeBeamCone()
        beamConeNode.position = SCNVector3(0, -0.14, 0)
        gimbalNode.addChildNode(beamConeNode)

        // Glow light (stays fixed on container, near truss)
        let (glowLightNode, glowLight) = StageGeometry.makeGlowLight()
        glowLightNode.position = SCNVector3(0, 0.05, 0)
        container.addChildNode(glowLightNode)

        return FixtureSceneNodes(
            containerNode: container,
            gimbalNode: gimbalNode,
            bodyNode: bodyNode,
            yokeNode: yokeNode,
            spotLight: spotLight,
            spotLightNode: spotLightNode,
            beamConeNode: beamConeNode,
            beamMaterial: beamMaterial,
            glowLight: glowLight
        )
    }

    // MARK: - Center-Out Positioning

    private func trussXPosition(slotIndex: Int, totalFixtures: Int) -> Float {
        StageGeometry.trussXPosition(
            slotIndex: slotIndex,
            totalFixtures: totalFixtures,
            trussLength: StageGeometry.trussLength
        )
    }
}
