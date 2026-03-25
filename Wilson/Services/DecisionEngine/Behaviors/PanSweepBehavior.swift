import Foundation

/// Sinusoidal pan sweep synced to bars. Fixtures get phase offsets based on
/// position to create fan-out or converge patterns.
struct PanSweepBehavior: Behavior {
    static let id = "panSweep"

    let controlledAttributes: Set<FixtureAttribute> = [.pan, .panFine]

    func evaluate(
        fixtures: [StageFixture],
        context: BehaviorContext
    ) -> [UUID: [FixtureAttribute: Double]] {
        guard !context.musicalState.isSilent else { return [:] }

        let speed = context.parameters.speed
        let intensity = context.parameters.intensity
        let movementScale = context.movementIntensity

        // One full sweep per 8 beats, using continuous time for smooth motion
        let beatsPerSecond = max(1, context.beat.bpm) / 60.0
        let cyclesPerSecond = beatsPerSecond / 8.0 * speed
        let basePhase = context.time * cyclesPerSecond + context.parameters.offset

        var result: [UUID: [FixtureAttribute: Double]] = [:]

        for (index, fixture) in fixtures.enumerated() {
            guard fixture.attributes.contains(.pan) else { continue }

            // Fan-out: offset each fixture's phase by position for spread
            let fixtureOffset: Double
            if fixtures.count > 1 {
                fixtureOffset = Double(index) / Double(fixtures.count) * 0.3
            } else {
                fixtureOffset = 0
            }

            let phase = basePhase + fixtureOffset
            let amplitude = 0.4 * intensity * movementScale
            let pan = 0.5 + amplitude * sin(phase * 2 * .pi)

            var attrs: [FixtureAttribute: Double] = [.pan: max(0, min(1, pan))]

            // Fine channel for smooth sub-step movement
            if fixture.attributes.contains(.panFine) {
                let fineFraction = (pan * 255).truncatingRemainder(dividingBy: 1.0)
                attrs[.panFine] = fineFraction
            }

            result[fixture.id] = attrs
        }

        return result
    }
}
