import Foundation

/// Slew-rate limiter for pan/tilt to prevent jerky motion on moving heads.
/// Caps the rate of change per frame to ensure smooth physical movement.
struct MovementLimiter: Sendable {
    /// Maximum change per second for pan/tilt (0–1 normalized range).
    /// 1.5 means a full sweep takes ~0.67 seconds minimum.
    var maxRatePerSecond: Double = 1.5

    /// Apply rate limiting to movement attributes.
    func apply(to state: inout FixtureState, previous: FixtureState?, deltaTime: Double) {
        guard let previous, deltaTime > 0 else { return }

        let maxDelta = maxRatePerSecond * deltaTime

        for attr in [FixtureAttribute.pan, .panFine, .tilt, .tiltFine] {
            guard let target = state.attributes[attr],
                  let prev = previous.attributes[attr] else { continue }

            let diff = target - prev
            if abs(diff) > maxDelta {
                state.attributes[attr] = prev + (diff > 0 ? maxDelta : -maxDelta)
            }
        }
    }
}
