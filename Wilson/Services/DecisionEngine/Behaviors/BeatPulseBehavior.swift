import Foundation

/// Pulses dimmer on beat with configurable decay curve.
/// Decay shape adapts to energy: punchy music gets fast cubic decay,
/// mellow music gets slower exponential decay.
///
/// Variant 0 (default): fires on every beat.
/// Variant 1 (alternating): fires on even beats only (0 & 2 in a 4/4 bar).
///   Use `offset: 1.0` for the complementary group to fire on odd beats (1 & 3).
struct BeatPulseBehavior: Behavior {
    static let id = "beatPulse"

    let controlledAttributes: Set<FixtureAttribute> = [.dimmer]

    enum Mode: Int, Sendable {
        /// Fires on every beat.
        case everyBeat = 0
        /// Fires on even beats only. Offset by 1.0 for odd beats.
        case alternating = 1
    }

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
        let mode = Mode(rawValue: context.parameters.variant) ?? .everyBeat

        // In alternating mode, only fire on every other beat
        if mode == .alternating {
            let shifted = ms.beatPosition + context.parameters.offset
            let beatIndex = Int(shifted) % 4
            if !beatIndex.isMultiple(of: 2) {
                // This is an off-beat for this group — stay dark
                return fixtures.reduce(into: [:]) { result, fixture in
                    result[fixture.id] = [.dimmer: 0]
                }
            }
        }

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
            result[fixture.id] = [.dimmer: scaled]
        }
    }
}
