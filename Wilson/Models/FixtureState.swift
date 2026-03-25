import Foundation

/// Per-fixture attribute state produced by the decision engine.
/// All values are normalized 0.0–1.0. This is the abstraction boundary
/// between lighting decisions and output backends (DMX, virtual rendering).
struct FixtureState: Sendable {
    let fixtureID: UUID
    var attributes: [FixtureAttribute: Double] = [:]

    var dimmer: Double { attributes[.dimmer] ?? 0 }

    var color: LightColor {
        LightColor(
            red: attributes[.red] ?? 0,
            green: attributes[.green] ?? 0,
            blue: attributes[.blue] ?? 0,
            white: attributes[.white] ?? 0
        )
    }
}
