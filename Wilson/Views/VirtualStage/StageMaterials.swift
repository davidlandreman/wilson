import SceneKit

/// Material presets for the 3D stage scene.
enum StageMaterials {

    /// Silver metallic finish for the lighting truss.
    static func trussMetal() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .blinn
        material.diffuse.contents = NSColor(red: 0.35, green: 0.37, blue: 0.40, alpha: 1)
        material.specular.contents = NSColor(white: 0.5, alpha: 1)
        material.shininess = 0.4
        material.ambient.contents = NSColor(red: 0.30, green: 0.32, blue: 0.35, alpha: 1)
        return material
    }

    /// Dark metallic finish for par can housings.
    static func parCanHousing() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .blinn
        material.diffuse.contents = NSColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1)
        material.specular.contents = NSColor(white: 0.3, alpha: 1)
        material.shininess = 0.3
        material.ambient.contents = NSColor(red: 0.15, green: 0.15, blue: 0.17, alpha: 1)
        return material
    }

    /// Dark stage floor — picks up colored light from fixtures.
    static func stageFloor() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .blinn
        material.diffuse.contents = NSColor(white: 0.20, alpha: 1)
        material.specular.contents = NSColor(white: 0.25, alpha: 1)
        material.shininess = 0.2
        material.ambient.contents = NSColor(white: 0.05, alpha: 1)
        return material
    }

    /// Additive-blend material for visible light beam cone.
    /// Single-sided: only outward-facing triangles render, halving overlap.
    /// Brightness controlled via diffuse color, not transparency.
    static func beamMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = NSColor.black // off by default
        material.blendMode = .add
        material.isDoubleSided = false
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        return material
    }

    /// Dark wall — faintly visible to give room depth.
    static func darkWall() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .blinn
        material.diffuse.contents = NSColor(white: 0.06, alpha: 1)
        material.specular.contents = NSColor(white: 0.0, alpha: 1)
        material.ambient.contents = NSColor(white: 0.04, alpha: 1)
        return material
    }
}
