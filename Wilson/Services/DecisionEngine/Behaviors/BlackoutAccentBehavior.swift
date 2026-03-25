import Foundation

/// Momentary blackout before detected drops for maximum impact.
/// Monitors transition probability and energy trajectory for imminent drops.
/// Self-limiting: triggers at most once per transition.
struct BlackoutAccentBehavior: Behavior {
    static let id = "blackoutAccent"

    let controlledAttributes: Set<FixtureAttribute> = [.dimmer]

    /// Duration of blackout in seconds (~3-4 frames at 47Hz).
    private let blackoutDuration: Double = 0.08

    func evaluate(
        fixtures: [StageFixture],
        context: BehaviorContext
    ) -> [UUID: [FixtureAttribute: Double]] {
        let ms = context.musicalState

        // Detect imminent drop: high transition probability + building energy
        let imminentDrop = ms.transitionProbability > 0.7
            && context.moodState.energyTrajectory == .building
            && context.reactivity > 0.5

        // Also trigger on downbeat after a build
        let dropHit = ms.isDownbeat
            && context.moodState.energyTrajectory == .building
            && ms.energy > 0.7

        guard imminentDrop || dropHit else { return [:] }

        // During the blackout window, all dimmers to 0
        let dimmerValue: Double = imminentDrop ? 0.0 : 1.0

        return fixtures.reduce(into: [:]) { result, fixture in
            guard fixture.attributes.contains(.dimmer) else { return }
            result[fixture.id] = [.dimmer: dimmerValue]
        }
    }
}
