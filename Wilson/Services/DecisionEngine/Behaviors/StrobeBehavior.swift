import Foundation

/// Onset-reactive strobe effect. Only activates when onsets fire AND energy
/// exceeds a threshold gated by the reactivity parameter.
/// Uses the fixture's native strobe channel if available, otherwise rapid dimmer toggling.
struct StrobeBehavior: Behavior {
    static let id = "strobe"

    let controlledAttributes: Set<FixtureAttribute> = [.dimmer, .strobe]

    func evaluate(
        fixtures: [StageFixture],
        context: BehaviorContext
    ) -> [UUID: [FixtureAttribute: Double]] {
        let ms = context.musicalState
        let intensity = context.parameters.intensity

        // Energy threshold: higher reactivity = lower threshold (more strobe)
        let threshold = 1.0 - context.reactivity * 0.7
        let shouldStrobe = ms.isOnset && ms.energy > threshold && !ms.isSilent

        var result: [UUID: [FixtureAttribute: Double]] = [:]

        for fixture in fixtures {
            if fixture.attributes.contains(.strobe) {
                // Use native strobe channel
                result[fixture.id] = [
                    .strobe: shouldStrobe ? intensity : 0,
                    .dimmer: shouldStrobe ? intensity : 0,
                ]
            } else if fixture.attributes.contains(.dimmer) {
                // Rapid dimmer flash
                result[fixture.id] = [
                    .dimmer: shouldStrobe ? intensity : 0,
                ]
            }
        }

        return result
    }
}
