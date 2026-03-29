import Foundation

/// Multi-mode strobe effect. Mode selected via `parameters.variant`:
///   0 = onset-reactive (fires on transients above energy threshold)
///   1 = half-time (beats 1 & 3 only, short flash)
///   2 = subdivision (eighth-note rapid strobe, gated by energy)
///   3 = punchy (downbeat-only flash with sharp decay)
///
/// All modes output 0 when not firing so HTP compositing with BeatPulseBehavior
/// gives a pulse floor with strobe punctuation on top.
struct StrobeBehavior: Behavior {
    static let id = "strobe"

    let controlledAttributes: Set<FixtureAttribute> = [.dimmer, .strobe]

    enum Mode: Int, Sendable {
        /// Fires on musical onsets when energy exceeds a reactivity-gated threshold.
        case onsetReactive = 0
        /// Fires on beats 1 and 3 only (every other beat), short flash.
        case halfTime = 1
        /// Rapid eighth-note strobe, gated by energy > 0.4.
        /// Falls back to quarter-note at BPM > 150 for safety.
        case subdivision = 2
        /// Downbeat-only flash with sharp exponential decay.
        case punchy = 3
    }

    func evaluate(
        fixtures: [StageFixture],
        context: BehaviorContext
    ) -> [UUID: [FixtureAttribute: Double]] {
        let ms = context.musicalState
        guard !ms.isSilent else { return [:] }

        let intensity = context.parameters.intensity
        let mode = Mode(rawValue: context.parameters.variant) ?? .onsetReactive

        let dimmerValue: Double
        switch mode {
        case .onsetReactive:
            dimmerValue = evaluateOnsetReactive(context: context, intensity: intensity)
        case .halfTime:
            dimmerValue = evaluateHalfTime(context: context, intensity: intensity)
        case .subdivision:
            dimmerValue = evaluateSubdivision(context: context, intensity: intensity)
        case .punchy:
            dimmerValue = evaluatePunchy(context: context, intensity: intensity)
        }

        var result: [UUID: [FixtureAttribute: Double]] = [:]
        for fixture in fixtures {
            if fixture.attributes.contains(.strobe) {
                result[fixture.id] = [
                    .strobe: dimmerValue,
                    .dimmer: dimmerValue,
                ]
            } else if fixture.attributes.contains(.dimmer) {
                result[fixture.id] = [
                    .dimmer: dimmerValue,
                ]
            }
        }
        return result
    }

    // MARK: - Mode Implementations

    /// Original behavior: fires on onset when energy > reactivity-gated threshold.
    private func evaluateOnsetReactive(context: BehaviorContext, intensity: Double) -> Double {
        let ms = context.musicalState
        let threshold = 1.0 - context.reactivity * 0.7
        let shouldStrobe = ms.isOnset && ms.energy > threshold
        return shouldStrobe ? intensity : 0
    }

    /// Fires on beats 1 and 3 (every other beat). Short flash in the first 15% of the beat.
    private func evaluateHalfTime(context: BehaviorContext, intensity: Double) -> Double {
        let ms = context.musicalState
        let beatIndex = Int(ms.beatPosition)
        let isHalfTimeBeat = beatIndex == 0 || beatIndex == 2
        let isFlashWindow = ms.beatPhase < 0.15
        return (isHalfTimeBeat && isFlashWindow) ? intensity : 0
    }

    /// Eighth-note rapid strobe gated by energy. Falls back to quarter-note above 150 BPM.
    private func evaluateSubdivision(context: BehaviorContext, intensity: Double) -> Double {
        let ms = context.musicalState
        guard ms.energy > 0.4 else { return 0 }

        let speed = context.parameters.speed
        // At high BPM, use quarter notes instead of eighths for safety
        let subdivisions: Double = ms.bpm > 150 ? 1.0 : 2.0
        let subPhase = (ms.beatPhase * subdivisions * speed).truncatingRemainder(dividingBy: 1.0)

        // Flash for first 20% of each subdivision
        return subPhase < 0.2 ? intensity : 0
    }

    /// Downbeat-only (beat 1) flash with sharp exponential decay.
    private func evaluatePunchy(context: BehaviorContext, intensity: Double) -> Double {
        let ms = context.musicalState
        let beatIndex = Int(ms.beatPosition)
        guard beatIndex == 0 else { return 0 }

        // Sharp attack on beat 1, fast exponential decay
        let decay = exp(-ms.beatPhase * 12.0)
        return intensity * decay
    }
}
