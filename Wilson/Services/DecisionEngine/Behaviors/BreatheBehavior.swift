import Foundation

/// Smooth sine-wave dimming with phase offsets across fixtures.
/// Creates a wave effect along the truss. Period tied to BPM.
struct BreatheBehavior: Behavior {
    static let id = "breathe"

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

        let speed = context.parameters.speed
        let intensity = context.parameters.intensity

        // One full breath cycle per 2 bars (8 beats), using continuous time for smooth motion
        let beatsPerSecond = max(1, context.beat.bpm) / 60.0
        let cyclesPerSecond = beatsPerSecond / 8.0 * speed
        let cyclePhase = context.time * cyclesPerSecond + context.parameters.offset

        var result: [UUID: [FixtureAttribute: Double]] = [:]

        for fixture in fixtures {

            // Offset each fixture by trussSlot for wave effect
            let fixtureOffset: Double
            if fixtures.count > 1 {
                fixtureOffset = Double(fixture.trussSlot) / Double(fixtures.count) * 0.5
            } else {
                fixtureOffset = 0
            }

            let phase = (cyclePhase + fixtureOffset).truncatingRemainder(dividingBy: 1.0)
            // Sine wave mapped from [-1,1] to [minBrightness, 1.0]
            let minBrightness = 0.02
            let wave = (sin(phase * 2 * .pi) + 1) / 2  // 0–1
            let dimmer = (minBrightness + wave * (1.0 - minBrightness)) * intensity

            result[fixture.id] = [.dimmer: dimmer]
        }

        return result
    }
}
