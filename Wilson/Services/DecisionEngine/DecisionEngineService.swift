import Foundation

/// Translates MusicalState into lighting decisions.
/// Rule-based engine with weighted randomization, parameterized by the active cue.
@Observable
final class DecisionEngineService {
    private(set) var currentFrame = DMXFrame.blackout

    /// Active cue parameters influencing behavior.
    var reactivity: Double = 0.5       // 0 = subtle, 1 = aggressive
    var movementIntensity: Double = 0.5
    var colorTemperature: Double = 0.5 // 0 = cool, 1 = warm

    /// Generate the next DMX frame based on current musical state and fixture configuration.
    func update(musicalState: MusicalState, fixtures: [PatchedFixture], palette: ColorPalette?) {
        // TODO: Phase 3 — Implement decision engine:
        // 1. Energy-to-intensity mapping
        // 2. Beat-synchronized timing (phrase awareness)
        // 3. Segment-aware behavior rules
        // 4. Fixture coordination across groups
        // 5. Randomization with aesthetic coherence
        // 6. Cooldown logic for contrast/dynamics
    }
}
