import Foundation

/// Snaps tilt down on beat, smoothly returns up between beats.
/// Creates a "nodding" effect on moving heads. Amplitude scales with energy.
struct TiltBounceBehavior: Behavior {
    static let id = "tiltBounce"

    let controlledAttributes: Set<FixtureAttribute> = [.tilt, .tiltFine]

    func evaluate(
        fixtures: [StageFixture],
        context: BehaviorContext
    ) -> [UUID: [FixtureAttribute: Double]] {
        let ms = context.musicalState
        guard !ms.isSilent else { return [:] }

        let intensity = context.parameters.intensity
        let movementScale = context.movementIntensity

        // Bounce amplitude scales with energy
        let amplitude = 0.15 * ms.energy * intensity * movementScale

        // Exponential return: fast snap down, smooth return up
        let phase = context.beat.phase
        let bounce = amplitude * exp(-3.0 * phase) // Fast decay

        // Base tilt at audience-facing home position, bounce goes down (lower values)
        let tilt = MovementPatternBehavior.tiltHome - bounce

        var result: [UUID: [FixtureAttribute: Double]] = [:]

        for fixture in fixtures {
            guard fixture.attributes.contains(.tilt) else { continue }

            var attrs: [FixtureAttribute: Double] = [.tilt: max(0, min(1, tilt))]

            if fixture.attributes.contains(.tiltFine) {
                let fineFraction = (tilt * 255).truncatingRemainder(dividingBy: 1.0)
                attrs[.tiltFine] = fineFraction
            }

            result[fixture.id] = attrs
        }

        return result
    }
}
