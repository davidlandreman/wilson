import Foundation
import SwiftData

/// A color palette — a curated set of colors for the decision engine to pick from.
@Model
final class ColorPalette {
    var name: String
    var colors: [LightColor]

    init(name: String, colors: [LightColor]) {
        self.name = name
        self.colors = colors
    }
}

/// Simple RGB color representation for DMX output.
struct LightColor: Codable, Sendable {
    var red: Double   // 0.0–1.0
    var green: Double
    var blue: Double
    var white: Double

    static let off = LightColor(red: 0, green: 0, blue: 0, white: 0)
    static let warmWhite = LightColor(red: 1.0, green: 0.85, blue: 0.6, white: 1.0)
}

/// A cue combines a palette, behavior parameters, and fixture group assignments.
@Model
final class Cue {
    var name: String
    var palette: ColorPalette?
    var reactivity: Double      // 0.0 (subtle) – 1.0 (aggressive)
    var movementIntensity: Double
    var crossfadeDuration: Double // seconds

    init(name: String, palette: ColorPalette? = nil, reactivity: Double = 0.5, movementIntensity: Double = 0.5, crossfadeDuration: Double = 2.0) {
        self.name = name
        self.palette = palette
        self.reactivity = reactivity
        self.movementIntensity = movementIntensity
        self.crossfadeDuration = crossfadeDuration
    }
}
