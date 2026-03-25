import Foundation

/// Everything a behavior needs to compute fixture attributes for one frame.
struct BehaviorContext: Sendable {
    let musicalState: MusicalState
    let moodState: MoodState
    let palette: ResolvedPalette
    let beat: BeatContext
    /// Monotonic seconds since engine start.
    let time: Double
    /// Seconds since last frame (~0.021 at 47Hz).
    let deltaTime: Double
    /// 0 = subtle, 1 = aggressive (from active cue).
    let reactivity: Double
    /// 0 = still, 1 = maximum movement (from active cue).
    let movementIntensity: Double
    /// Parameters from the behavior slot.
    let parameters: BehaviorParameters
}

/// Beat timing information derived from MusicalState.
struct BeatContext: Sendable {
    /// Phase within current beat (0.0→1.0).
    let phase: Double
    /// Phase within current bar (0.0→1.0), derived from beatPosition / 4.0.
    let barPhase: Double
    /// Phase within a 4-bar phrase (0.0→1.0).
    let phrasePhase: Double
    /// Current BPM.
    let bpm: Double
    /// True on beat onset frame.
    let isBeat: Bool
    /// True on bar boundary (beat 1).
    let isDownbeat: Bool
    /// True on phrase boundary (every 4 bars).
    let isPhraseBoundary: Bool

    init(from musicalState: MusicalState, phraseCounter: Int) {
        self.phase = musicalState.beatPhase
        self.barPhase = musicalState.beatPosition / 4.0
        // phraseCounter counts bars; phrase = 4 bars
        let barInPhrase = phraseCounter % 4
        self.phrasePhase = (Double(barInPhrase) + self.barPhase) / 4.0
        self.bpm = musicalState.bpm
        self.isBeat = musicalState.isBeat
        self.isDownbeat = musicalState.isDownbeat
        self.isPhraseBoundary = musicalState.isDownbeat && (phraseCounter % 4 == 0)
    }
}

/// A palette resolved with color relationships and mood-influenced warm/cool bias.
struct ResolvedPalette: Sendable {
    let colors: [LightColor]
    /// 0 = cool bias, 1 = warm bias, influenced by spectral centroid + mood.
    let warmBias: Double

    /// Primary color from the palette.
    func primary() -> LightColor {
        guard !colors.isEmpty else { return .warmWhite }
        return warmShifted(colors[0])
    }

    /// Secondary color — contrasting with primary.
    func secondary() -> LightColor {
        guard colors.count >= 2 else { return primary() }
        // Pick the color furthest from primary in the palette
        let mid = colors.count / 2
        return warmShifted(colors[mid])
    }

    /// Accent color for visual pop.
    func accent() -> LightColor {
        guard colors.count >= 3 else { return secondary() }
        return warmShifted(colors[colors.count - 1])
    }

    /// Cycle through palette colors by index (wraps around).
    func colorForIndex(_ index: Int) -> LightColor {
        guard !colors.isEmpty else { return .warmWhite }
        return warmShifted(colors[index % colors.count])
    }

    /// Interpolate between two palette colors.
    func interpolated(from: Int, to: Int, t: Double) -> LightColor {
        let a = colorForIndex(from)
        let b = colorForIndex(to)
        return a.lerp(to: b, t: t)
    }

    /// Apply warm/cool bias to a color.
    func warmShifted(_ color: LightColor) -> LightColor {
        color.warmCoolShifted(warmBias: warmBias)
    }
}
