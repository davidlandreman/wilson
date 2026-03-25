import Foundation

/// Slowly-evolving emotional state derived from sustained musical features.
/// All dimensions are 0.0–1.0, updated via exponential moving average.
struct MoodState: Sendable {
    /// Energy + BPM contribution. High = energetic, low = calm.
    var excitement: Double = 0.5

    /// Major/minor key influence. High = happy/bright, low = sad/dark.
    var valence: Double = 0.5

    /// Spectral centroid influence. High = bright/airy, low = dark/heavy.
    var brightness: Double = 0.5

    /// Spectral flatness influence. High = chaotic/noisy, low = ordered/tonal.
    var chaos: Double = 0.3

    /// Overall energy envelope (smoothed via asymmetric EMA on peak envelope).
    var intensity: Double = 0.5

    /// Peak energy in the recent beat-length window (raw, not smoothed).
    var peakEnergy: Double = 0.0

    /// Which direction energy is trending.
    var energyTrajectory: EnergyTrajectory = .stable
}

/// Direction of energy over a recent time window.
enum EnergyTrajectory: Sendable {
    /// Energy increasing over recent window.
    case building
    /// Energy stable at a high level.
    case sustaining
    /// Energy decreasing.
    case declining
    /// Energy stable at moderate/low level.
    case stable
}
