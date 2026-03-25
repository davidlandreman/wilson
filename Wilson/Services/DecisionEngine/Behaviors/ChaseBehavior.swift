import Foundation

/// Sequential fixture activation along trussSlot ordering, synced to BPM.
/// Speed: one full chase per beat (high energy) or per bar (low energy).
/// Direction alternates each cycle.
struct ChaseBehavior: Behavior {
    static let id = "chase"

    let controlledAttributes: Set<FixtureAttribute> = [.dimmer]

    func evaluate(
        fixtures: [StageFixture],
        context: BehaviorContext
    ) -> [UUID: [FixtureAttribute: Double]] {
        let ms = context.musicalState
        guard !ms.isSilent, fixtures.count > 1 else {
            return fixtures.reduce(into: [:]) { result, fixture in
                result[fixture.id] = [.dimmer: 0]
            }
        }

        let intensity = context.parameters.intensity
        let speed = context.parameters.speed

        // Chase phase: bar-level for moderate, beat-level for fast
        let chasePhase: Double
        if context.moodState.excitement > 0.6 {
            // Per-beat chase
            chasePhase = context.beat.phase * speed
        } else {
            // Per-bar chase
            chasePhase = context.beat.barPhase * speed
        }

        // Alternate direction each bar
        let barIndex = Int(context.beat.barPhase * 4)
        let reversed = barIndex.isMultiple(of: 2)

        // Sort fixtures by trussSlot for spatial ordering
        let sorted = fixtures.sorted { $0.trussSlot < $1.trussSlot }
        let count = Double(sorted.count)

        var result: [UUID: [FixtureAttribute: Double]] = [:]

        for (index, fixture) in sorted.enumerated() {
            guard fixture.attributes.contains(.dimmer) else { continue }

            let normalizedPos: Double
            if reversed {
                normalizedPos = Double(sorted.count - 1 - index) / count
            } else {
                normalizedPos = Double(index) / count
            }

            // Gaussian window around chase position for smooth falloff
            let distance = abs(chasePhase.truncatingRemainder(dividingBy: 1.0) - normalizedPos)
            let wrappedDistance = min(distance, 1.0 - distance)
            let width = 1.0 / count * 1.5 // Wider than one fixture for smooth blending
            let dimmer = exp(-wrappedDistance * wrappedDistance / (2 * width * width)) * intensity

            result[fixture.id] = [.dimmer: dimmer]
        }

        return result
    }
}
