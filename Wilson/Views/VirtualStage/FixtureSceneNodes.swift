import SceneKit

/// Groups the SceneKit nodes for a single fixture, enabling O(1) property updates.
/// Used only on @MainActor — contains non-Sendable SCNNode references.
struct FixtureSceneNodes {
    let containerNode: SCNNode
    let gimbalNode: SCNNode   // tilt rotation — parents body, spot, and beam
    let bodyNode: SCNNode
    let yokeNode: SCNNode
    let spotLight: SCNLight
    let spotLightNode: SCNNode
    let beamConeNode: SCNNode
    let beamMaterial: SCNMaterial
    let glowLight: SCNLight
}
