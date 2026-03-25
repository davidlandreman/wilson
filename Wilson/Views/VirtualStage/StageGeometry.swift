import SceneKit

/// Factory methods for procedural 3D stage geometry.
enum StageGeometry {

    // MARK: - Scene Constants

    static let trussLength: Float = 5.0
    static let trussHeight: Float = 3.5
    static let trussDepth: Float = -1.0 // slightly upstage
    static let trussSection: Float = 0.30 // cross-section width/height
    static let railRadius: Float = 0.04  // ~8cm diameter — visible from audience distance

    static let beamHeight: Float = 3.15 // extends slightly into floor so cone meets spot pool
    static let beamTopRadius: CGFloat = 0.02
    static let beamBottomRadius: CGFloat = 0.55

    // MARK: - Stage Floor

    static func makeFloor() -> SCNNode {
        let floor = SCNFloor()
        floor.reflectivity = 0.08
        floor.reflectionFalloffEnd = 2.0
        floor.firstMaterial = StageMaterials.stageFloor()
        let node = SCNNode(geometry: floor)
        node.name = "stageFloor"
        return node
    }

    // MARK: - Back Wall

    static func makeBackWall() -> SCNNode {
        let wall = SCNBox(width: 12, height: 6, length: 0.1, chamferRadius: 0)
        wall.firstMaterial = StageMaterials.darkWall()
        let node = SCNNode(geometry: wall)
        node.name = "backWall"
        node.position = SCNVector3(0, 3, -4)
        return node
    }

    // MARK: - Lighting Truss

    /// Build a box-frame truss from cylinders and cross-braces.
    static func makeTruss(length: Float = trussLength) -> SCNNode {
        let parent = SCNNode()
        parent.name = "truss"
        parent.position = SCNVector3(0, trussHeight, trussDepth)

        let half = trussSection / 2
        let material = StageMaterials.trussMetal()

        // Four horizontal rails along X axis
        let railCorners: [(Float, Float)] = [
            (-half, -half), (half, -half),
            (-half, half), (half, half),
        ]
        for (y, z) in railCorners {
            let rail = SCNCylinder(radius: CGFloat(railRadius), height: CGFloat(length))
            rail.radialSegmentCount = 12
            rail.firstMaterial = material
            let node = SCNNode(geometry: rail)
            // Rotate cylinder from Y-axis to X-axis
            node.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
            node.position = SCNVector3(0, y, z)
            parent.addChildNode(node)
        }

        // Cross-braces at regular intervals
        let braceSpacing: Float = 0.5
        let braceCount = Int(length / braceSpacing)
        let braceRadius: Float = 0.025

        for i in 0...braceCount {
            let x = -length / 2 + Float(i) * braceSpacing

            // Vertical braces (front and back)
            for z in [-half, half] {
                let brace = SCNCylinder(radius: CGFloat(braceRadius), height: CGFloat(trussSection))
                brace.radialSegmentCount = 8
                brace.firstMaterial = material
                let node = SCNNode(geometry: brace)
                node.position = SCNVector3(x, 0, z)
                parent.addChildNode(node)
            }

            // Horizontal cross-brace (top and bottom)
            for y in [-half, half] {
                let brace = SCNCylinder(radius: CGFloat(braceRadius), height: CGFloat(trussSection))
                brace.radialSegmentCount = 8
                brace.firstMaterial = material
                let node = SCNNode(geometry: brace)
                node.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
                node.position = SCNVector3(x, y, 0)
                parent.addChildNode(node)
            }
        }

        return parent
    }

    // MARK: - Par Can Fixture

    /// Returns (bodyNode, yokeNode) for a par can fixture.
    static func makeParCan() -> (body: SCNNode, yoke: SCNNode) {
        let material = StageMaterials.parCanHousing()

        // Body: truncated cone (par can shape) — scaled for visibility
        let body = SCNCone(topRadius: 0.10, bottomRadius: 0.15, height: 0.25)
        body.radialSegmentCount = 24
        body.firstMaterial = material
        let bodyNode = SCNNode(geometry: body)
        bodyNode.name = "parCanBody"

        // Yoke: U-bracket — two side arms + crossbar
        let yokeNode = SCNNode()
        yokeNode.name = "yoke"

        let armLength: Float = 0.30
        let armRadius: CGFloat = 0.015
        let armSpread: Float = 0.16

        for side in [-1.0, 1.0] as [Float] {
            let arm = SCNCylinder(radius: armRadius, height: CGFloat(armLength))
            arm.radialSegmentCount = 8
            arm.firstMaterial = material
            let armNode = SCNNode(geometry: arm)
            armNode.position = SCNVector3(side * armSpread, 0, 0)
            yokeNode.addChildNode(armNode)
        }

        // Crossbar connecting to truss
        let crossbar = SCNCylinder(radius: armRadius, height: CGFloat(armSpread * 2))
        crossbar.radialSegmentCount = 8
        crossbar.firstMaterial = material
        let crossbarNode = SCNNode(geometry: crossbar)
        crossbarNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        crossbarNode.position = SCNVector3(0, armLength / 2, 0)
        yokeNode.addChildNode(crossbarNode)

        return (body: bodyNode, yoke: yokeNode)
    }

    // MARK: - Light Beam

    /// Creates a cone representing a visible light beam.
    /// Single-sided rendering: only outward-facing triangles render, so from the
    /// camera only ~half the segments overlap additively (keeping brightness controlled).
    /// Returns (node, material) — material reference is kept for fast color/opacity updates.
    static func makeBeamCone(height: Float = beamHeight) -> (node: SCNNode, material: SCNMaterial) {
        let cone = SCNCone(
            topRadius: beamTopRadius,
            bottomRadius: beamBottomRadius,
            height: CGFloat(height)
        )
        cone.radialSegmentCount = 16
        let material = StageMaterials.beamMaterial()
        cone.firstMaterial = material

        let node = SCNNode(geometry: cone)
        node.name = "beamCone"
        // Pivot at top of cone so it hangs from the fixture
        node.pivot = SCNMatrix4MakeTranslation(0, CGFloat(height) / 2, 0)

        return (node: node, material: material)
    }

    // MARK: - Camera

    static func makeCamera() -> SCNNode {
        let camera = SCNCamera()
        camera.fieldOfView = 50
        camera.zNear = 0.1
        camera.zFar = 100

        let node = SCNNode()
        node.name = "camera"
        node.camera = camera
        node.position = SCNVector3(0, 1.8, 7)
        // Explicit orientation: look toward stage (negative Z), tilted slightly up
        // atan2(2.0 - 1.8, 7.0) ≈ 0.0286 rad ≈ 1.6° up — almost horizontal
        node.eulerAngles = SCNVector3(-0.15, 0, 0) // tilt ~8.6° up to frame the truss

        return node
    }

    // MARK: - Ambient Light

    static func makeAmbientLight() -> SCNNode {
        let light = SCNLight()
        light.type = .ambient
        light.color = NSColor(red: 0.30, green: 0.30, blue: 0.40, alpha: 1)
        light.intensity = 500

        let node = SCNNode()
        node.name = "ambientLight"
        node.light = light

        return node
    }

    /// Dim omni light near the camera so the truss is faintly visible.
    static func makeFillLight() -> SCNNode {
        let light = SCNLight()
        light.type = .omni
        light.color = NSColor(red: 0.3, green: 0.3, blue: 0.4, alpha: 1)
        light.intensity = 500
        light.attenuationStartDistance = 2
        light.attenuationEndDistance = 15
        light.castsShadow = false

        let node = SCNNode()
        node.name = "fillLight"
        node.light = light
        node.position = SCNVector3(0, 4, 5)

        return node
    }

    // MARK: - Center-Out Positioning

    /// Convert a truss slot index to an X position on the truss.
    /// Slot 0 = center, then alternating right/left outward.
    static func trussXPosition(slotIndex: Int, totalFixtures: Int, trussLength: Float) -> Float {
        guard totalFixtures > 0 else { return 0 }

        let spacing = trussLength / Float(totalFixtures + 1)

        if slotIndex == 0 {
            return 0
        }

        let offset = (slotIndex + 1) / 2
        let sign: Float = slotIndex.isMultiple(of: 2) ? -1 : 1
        return sign * Float(offset) * spacing
    }

    // MARK: - Spot Light (per fixture)

    static func makeSpotLight() -> (node: SCNNode, light: SCNLight) {
        let light = SCNLight()
        light.type = .spot
        light.color = NSColor.white
        light.intensity = 0
        light.spotInnerAngle = 10
        light.spotOuterAngle = 22
        light.attenuationStartDistance = 0
        light.attenuationEndDistance = 8
        light.castsShadow = true
        light.shadowRadius = 3
        light.shadowSampleCount = 4
        light.shadowMode = .forward

        let node = SCNNode()
        node.name = "spotLight"
        node.light = light
        // Point downward
        node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)

        return (node: node, light: light)
    }
}
