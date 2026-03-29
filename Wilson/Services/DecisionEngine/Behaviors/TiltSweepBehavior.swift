import Foundation

/// Smooth tilt sweep from straight down (floor) to horizontal (above audience) and back.
/// Adjacent movers are 180° out of phase so when one points at the floor, its neighbor
/// points out above the audience. One full cycle per 4 beats by default.
struct TiltSweepBehavior: Behavior {
    static let id = "tiltSweep"

    let controlledAttributes: Set<FixtureAttribute> = [.tilt, .tiltFine]

    /// Tilt value for straight down at the floor.
    private let tiltFloor: Double = 0.0
    /// Tilt value for horizontal — beam parallel to the ground, above the audience.
    private let tiltHorizontal: Double = 0.5

    func evaluate(
        fixtures: [StageFixture],
        context: BehaviorContext
    ) -> [UUID: [FixtureAttribute: Double]] {
        guard !context.musicalState.isSilent else { return [:] }

        let speed = context.parameters.speed
        let movementScale = context.movementIntensity

        // One full cycle per 4 beats, using monotonic time for smooth motion
        let beatsPerSecond = max(1, context.beat.bpm) / 60.0
        let cyclesPerSecond = beatsPerSecond / 4.0 * speed
        let basePhase = context.time * cyclesPerSecond + context.parameters.offset

        var result: [UUID: [FixtureAttribute: Double]] = [:]

        for (index, fixture) in fixtures.enumerated() {
            guard fixture.attributes.contains(.tilt) else { continue }

            // Alternate phase: even-indexed fixtures start at floor, odd start at horizontal
            let alternateOffset = Double(index) * 0.5
            let phase = basePhase + alternateOffset

            // Sinusoidal sweep: 0→1→0 mapped to floor→horizontal→floor
            // Using (1 - cos) / 2 for smooth turnaround at both endpoints
            let sweep = (1.0 - cos(phase * 2.0 * .pi)) / 2.0

            // Scale the sweep range by movementIntensity
            let range = (tiltHorizontal - tiltFloor) * movementScale
            let tilt = tiltFloor + range * sweep

            var attrs: [FixtureAttribute: Double] = [.tilt: max(0, min(1, tilt))]

            if fixture.attributes.contains(.tiltFine) {
                let fineFraction = (tilt * 255).truncatingRemainder(dividingBy: 1.0)
                attrs[.tiltFine] = max(0, fineFraction)
            }

            result[fixture.id] = attrs
        }

        return result
    }
}
