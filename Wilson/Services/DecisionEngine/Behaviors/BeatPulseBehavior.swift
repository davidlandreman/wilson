import Foundation

/// Pulses dimmer on beat with configurable decay curve.
/// Decay shape adapts to energy: punchy music gets fast cubic decay,
/// mellow music gets slower exponential decay.
struct BeatPulseBehavior: Behavior {
    static let id = "beatPulse"

    let controlledAttributes: Set<FixtureAttribute> = [.dimmer]

    func evaluate(
        fixtures: [StageFixture],
        context: BehaviorContext
    ) -> [UUID: [FixtureAttribute: Double]] {
        let ms = context.musicalState
        guard !ms.isSilent else {
            return fixtures.reduce(into: [:]) { result, fixture in
                result[fixture.id] = [.dimmer: 0]
            }
        }

        let intensity = context.parameters.intensity
        let phase = context.beat.phase

        // Adaptive decay: high energy/crest = sharp cubic, low energy = softer exponential
        let sharpness = ms.energy * 0.7 + ms.crestFactor * 0.3
        let dimmerValue: Double
        if ms.isBeat {
            dimmerValue = 1.0
        } else if sharpness > 0.5 {
            // Cubic decay — punchy
            let decay = 1.0 - phase
            dimmerValue = decay * decay * decay
        } else {
            // Exponential decay — smoother
            dimmerValue = exp(-4.0 * phase)
        }

        let scaled = dimmerValue * intensity
        return fixtures.reduce(into: [:]) { result, fixture in
            guard fixture.attributes.contains(.dimmer) else { return }
            result[fixture.id] = [.dimmer: scaled]
        }
    }
}
