import Foundation

/// Translates MusicalState into per-fixture lighting states.
/// Produces FixtureState values — the abstraction boundary between
/// lighting decisions and output backends (DMX, virtual rendering).
@Observable
final class DecisionEngineService {
    private(set) var fixtureStates: [UUID: FixtureState] = [:]

    /// Active cue parameters influencing behavior.
    var reactivity: Double = 0.5       // 0 = subtle, 1 = aggressive
    var movementIntensity: Double = 0.5
    var colorTemperature: Double = 0.5 // 0 = cool, 1 = warm

    /// Generate fixture states based on current musical state and stage fixtures.
    func update(musicalState: MusicalState, fixtures: [StageFixture]) {
        var states: [UUID: FixtureState] = [:]

        for fixture in fixtures {
            var state = FixtureState(fixtureID: fixture.id)

            if fixture.attributes.contains(.dimmer) {
                // Beat-reactive strobe: full on at beat, cubic decay between beats
                if musicalState.isSilent {
                    state.attributes[.dimmer] = 0
                } else if musicalState.isBeat {
                    state.attributes[.dimmer] = 1.0
                } else {
                    let decay = 1.0 - musicalState.beatPhase
                    state.attributes[.dimmer] = decay * decay * decay
                }
            }

            // RGB fixtures get white on strobe for now
            if fixture.attributes.contains(.red) {
                let intensity = state.dimmer
                state.attributes[.red] = intensity
                state.attributes[.green] = intensity
                state.attributes[.blue] = intensity
            }

            states[fixture.id] = state
        }

        fixtureStates = states
    }
}
