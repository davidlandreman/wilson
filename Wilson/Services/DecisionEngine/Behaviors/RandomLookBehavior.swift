import Foundation

/// Positions movers at random audience-facing positions, holding each for a
/// musically-meaningful duration then smoothly transitioning to a new target.
/// Each fixture gets independently randomized targets, creating visual variety
/// when multiple movers share this behavior.
struct RandomLookBehavior: Behavior {
    static let id = "randomLook"

    let controlledAttributes: Set<FixtureAttribute> = [.pan, .tilt, .panFine, .tiltFine]

    /// How many beats to hold each position before transitioning.
    private let holdBeats: Double = 8.0
    /// Fraction of the hold period spent transitioning (0.0–1.0).
    private let transitionFraction: Double = 0.25

    func evaluate(
        fixtures: [StageFixture],
        context: BehaviorContext
    ) -> [UUID: [FixtureAttribute: Double]] {
        guard !context.musicalState.isSilent else { return [:] }

        let movementScale = context.movementIntensity
        let intensity = context.parameters.intensity

        // Time in beats since engine start
        let beatsPerSecond = max(1, context.beat.bpm) / 60.0
        let beatTime = context.time * beatsPerSecond * context.parameters.speed

        var result: [UUID: [FixtureAttribute: Double]] = [:]

        for (fixtureIndex, fixture) in fixtures.enumerated() {
            guard fixture.attributes.contains(.pan) || fixture.attributes.contains(.tilt) else {
                continue
            }

            // Offset each fixture's look cycle so they don't all transition simultaneously.
            // Fixture 0 changes on lookIndex, fixture 1 changes half a cycle later, etc.
            let fixtureOffset = Double(fixtureIndex) * 0.37 // irrational-ish spacing
            let offsetBeatTime = beatTime + fixtureOffset * holdBeats
            let fixtureLoopIndex = Int(offsetBeatTime / holdBeats)
            let fixturePhase = (offsetBeatTime / holdBeats).truncatingRemainder(dividingBy: 1.0)

            // Generate deterministic random positions from the look index + fixture index
            let currentTarget = randomPosition(seed: fixtureLoopIndex, fixtureIndex: fixtureIndex, intensity: intensity)
            let previousTarget = randomPosition(seed: fixtureLoopIndex - 1, fixtureIndex: fixtureIndex, intensity: intensity)

            // Smooth transition at the start of each hold period
            let pan: Double
            let tilt: Double
            if fixturePhase < transitionFraction {
                // Transitioning from previous to current
                let t = easeInOut(fixturePhase / transitionFraction)
                pan = previousTarget.pan + (currentTarget.pan - previousTarget.pan) * t
                tilt = previousTarget.tilt + (currentTarget.tilt - previousTarget.tilt) * t
            } else {
                // Holding at current position
                pan = currentTarget.pan
                tilt = currentTarget.tilt
            }

            // Scale movement range by movementIntensity
            let scaledPan = 0.5 + (pan - 0.5) * movementScale
            let scaledTilt = MovementPatternBehavior.tiltHome + (tilt - MovementPatternBehavior.tiltHome) * movementScale

            var attrs: [FixtureAttribute: Double] = [:]
            if fixture.attributes.contains(.pan) {
                attrs[.pan] = max(0, min(1, scaledPan))
            }
            if fixture.attributes.contains(.tilt) {
                attrs[.tilt] = max(0, min(1, scaledTilt))
            }
            if fixture.attributes.contains(.panFine) {
                let fineFraction = (scaledPan * 255).truncatingRemainder(dividingBy: 1.0)
                attrs[.panFine] = max(0, fineFraction)
            }
            if fixture.attributes.contains(.tiltFine) {
                let fineFraction = (scaledTilt * 255).truncatingRemainder(dividingBy: 1.0)
                attrs[.tiltFine] = max(0, fineFraction)
            }
            result[fixture.id] = attrs
        }

        return result
    }

    /// Generate a deterministic pseudo-random audience-facing position.
    /// Pan: spread across the stage (0.15–0.85).
    /// Tilt: biased toward audience, with slight variation (tiltHome ± range).
    private func randomPosition(seed: Int, fixtureIndex: Int, intensity: Double) -> (pan: Double, tilt: Double) {
        // Simple hash for deterministic randomness
        let hash1 = pseudoRandom(seed: seed &* 2654435761 &+ fixtureIndex &* 340573321)
        let hash2 = pseudoRandom(seed: seed &* 1103515245 &+ fixtureIndex &* 214013 &+ 12345)

        // Pan: full stage spread, slightly narrower at low intensity
        let panRange = 0.35 * (0.5 + 0.5 * intensity)
        let pan = 0.5 + (hash1 * 2.0 - 1.0) * panRange

        // Tilt: audience-facing with variation. Range goes from ±0.10 to ±0.25
        let tiltRange = 0.10 + 0.15 * intensity
        let tilt = MovementPatternBehavior.tiltHome + (hash2 * 2.0 - 1.0) * tiltRange

        return (pan: pan, tilt: tilt)
    }

    /// Deterministic pseudo-random number in [0, 1) from an integer seed.
    private func pseudoRandom(seed: Int) -> Double {
        // xorshift-style mixing
        var x = UInt64(bitPattern: Int64(seed))
        x ^= x &>> 13
        x &*= 0x5bd1e995
        x ^= x &>> 15
        return Double(x & 0x7FFFFFFF) / Double(0x80000000)
    }

    /// Smooth ease-in-out curve (hermite interpolation).
    private func easeInOut(_ t: Double) -> Double {
        t * t * (3.0 - 2.0 * t)
    }
}
