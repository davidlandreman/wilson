import Foundation

/// The continuously updated output of the audio analysis pipeline.
/// Consumed by the Decision Engine to drive lighting decisions.
struct MusicalState: Sendable {
    // MARK: - Rhythm

    /// Estimated tempo in beats per minute.
    var bpm: Double = 0

    /// Confidence in the BPM estimate (0.0–1.0).
    var bpmConfidence: Double = 0

    /// Continuous phase within the current beat (0.0→1.0 sawtooth).
    var beatPhase: Double = 0

    /// Current beat position within a bar (0.0 ..< 4.0 for 4/4 time).
    var beatPosition: Double = 0

    /// True on the frame containing a detected beat onset.
    var isBeat: Bool = false

    /// True when beat 1 of a bar is detected.
    var isDownbeat: Bool = false

    // MARK: - Energy & Dynamics

    /// Overall energy level, adaptively normalized to 0.0–1.0.
    var energy: Double = 0

    /// Pre-normalization RMS energy (for debug/telemetry).
    var rawEnergy: Double = 0

    /// Current adaptive normalization ceiling (for debug/telemetry).
    var normalizationCeiling: Double = 0

    /// Instantaneous peak amplitude (0.0–1.0).
    var peakLevel: Double = 0

    /// Peak-to-RMS ratio normalized to 0.0–1.0. Higher = punchier transients.
    var crestFactor: Double = 0

    // MARK: - Spectral

    /// Energy per frequency band.
    var spectralProfile = SpectralProfile()

    /// Weighted mean frequency in Hz — brightness indicator.
    var spectralCentroid: Double = 0

    /// 0.0 = tonal (pure pitch), 1.0 = noise-like (white noise).
    var spectralFlatness: Double = 0

    /// Frequency of the loudest spectral bin in Hz.
    var dominantFrequency: Double = 0

    // MARK: - Visualization

    /// FFT magnitude bins (~1024 elements) for spectrum display.
    var magnitudeSpectrum: [Float] = []

    /// Recent audio samples (~2400 = ~50ms at 48kHz) for oscilloscope display.
    var waveformBuffer: [Float] = []

    // MARK: - Onsets

    /// True on any transient (drum hit, note attack) — superset of isBeat.
    var isOnset: Bool = false

    /// Onset strength (0.0–1.0), how far above the adaptive threshold.
    var onsetStrength: Double = 0

    // MARK: - Key Detection

    /// Pitch class energy distribution (12 elements: C, C#, D, ... B).
    var chromagram: [Double] = Array(repeating: 0, count: 12)

    /// Detected musical key.
    var detectedKey: MusicalKey = .unknown

    /// Confidence in the key estimate (0.0–1.0).
    var keyConfidence: Double = 0

    // MARK: - Structure (Phase 3)

    /// Detected song segment type.
    var segment: SongSegment = .unknown

    /// Probability that a musical transition is imminent (0.0–1.0).
    var transitionProbability: Double = 0

    // MARK: - State

    /// Whether audio is currently detected as silence.
    var isSilent: Bool = true
}

// MARK: - Supporting Types

struct SpectralProfile: Sendable {
    var subBass: Double = 0   // 20–60 Hz
    var bass: Double = 0      // 60–250 Hz
    var mids: Double = 0      // 250–2000 Hz
    var highs: Double = 0     // 2000–6000 Hz
    var presence: Double = 0  // 6000–20000 Hz
}

enum SongSegment: String, Sendable, CaseIterable {
    case intro
    case verse
    case chorus
    case bridge
    case build
    case drop
    case breakdown
    case outro
    case unknown
}

enum MusicalKey: String, Sendable, CaseIterable {
    case cMajor, cMinor
    case dbMajor, cSharpMinor
    case dMajor, dMinor
    case ebMajor, dSharpMinor
    case eMajor, eMinor
    case fMajor, fMinor
    case gbMajor, fSharpMinor
    case gMajor, gMinor
    case abMajor, gSharpMinor
    case aMajor, aMinor
    case bbMajor, aSharpMinor
    case bMajor, bMinor
    case unknown

    /// Display name (e.g. "C Major", "A Minor").
    var displayName: String {
        switch self {
        case .unknown: return "—"
        case .cMajor: return "C Major"
        case .cMinor: return "C Minor"
        case .dbMajor: return "D\u{266D} Major"
        case .cSharpMinor: return "C\u{266F} Minor"
        case .dMajor: return "D Major"
        case .dMinor: return "D Minor"
        case .ebMajor: return "E\u{266D} Major"
        case .dSharpMinor: return "D\u{266F} Minor"
        case .eMajor: return "E Major"
        case .eMinor: return "E Minor"
        case .fMajor: return "F Major"
        case .fMinor: return "F Minor"
        case .gbMajor: return "G\u{266D} Major"
        case .fSharpMinor: return "F\u{266F} Minor"
        case .gMajor: return "G Major"
        case .gMinor: return "G Minor"
        case .abMajor: return "A\u{266D} Major"
        case .gSharpMinor: return "G\u{266F} Minor"
        case .aMajor: return "A Major"
        case .aMinor: return "A Minor"
        case .bbMajor: return "B\u{266D} Major"
        case .aSharpMinor: return "A\u{266F} Minor"
        case .bMajor: return "B Major"
        case .bMinor: return "B Minor"
        }
    }
}
