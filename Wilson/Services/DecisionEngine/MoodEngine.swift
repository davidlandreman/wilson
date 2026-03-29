import Foundation

/// Tracks slowly-evolving emotional dimensions from sustained musical features.
/// Uses exponential moving averages with different time constants per dimension.
struct MoodEngine: Sendable {
    private(set) var state = MoodState()

    /// Short peak-hold buffer: tracks max energy over a beat-length window.
    /// Percussive material (EDM kicks with gaps) has low average RMS but high peaks;
    /// the peak envelope captures "how loud is this section" rather than "how loud is this instant."
    private var peakHoldBuffer: [Double] = []
    private static let peakHoldSize = 25 // ~530ms at 47Hz — covers one beat at ~114+ BPM

    /// Windowed energy history for trajectory detection (uses peak envelope, not raw RMS).
    private var energyHistory: [Double] = []
    private static let energyHistorySize = 100 // ~2 seconds at 47Hz

    /// Hysteresis: candidate trajectory must persist for N frames before committing.
    private var candidateTrajectory: EnergyTrajectory = .stable
    private var candidateFrameCount = 0
    /// Frames required before committing to a new trajectory.
    /// Building/sustaining commit faster (energy gains feel worse to miss);
    /// declining requires longer confirmation (false declines feel worse to trigger).
    private static let debounceUp = 5       // ~106ms at 47Hz
    private static let debounceDown = 12    // ~255ms at 47Hz

    /// Number of downbeats seen, for bar counting.
    private(set) var barCounter = 0

    mutating func update(musicalState: MusicalState, deltaTime: Double) {
        guard deltaTime > 0 else { return }

        // Peak-hold envelope: max energy in a beat-length window.
        // Percussive material (EDM kicks with gaps) has low average RMS but high peaks;
        // one kick per beat keeps the envelope high even though most frames are quiet gaps.
        peakHoldBuffer.append(musicalState.energy)
        if peakHoldBuffer.count > Self.peakHoldSize {
            peakHoldBuffer.removeFirst()
        }
        let peakEnergy = peakHoldBuffer.max() ?? musicalState.energy

        // EMA alpha from time constant: alpha = 1 - exp(-dt / tau)
        let excitementAlpha = emaAlpha(deltaTime: deltaTime, timeConstant: 2.0)
        let valenceAlpha = emaAlpha(deltaTime: deltaTime, timeConstant: 8.0)
        let brightnessAlpha = emaAlpha(deltaTime: deltaTime, timeConstant: 3.0)
        let chaosAlpha = emaAlpha(deltaTime: deltaTime, timeConstant: 4.0)

        // Excitement: peak energy + normalized BPM (120 = neutral)
        let normalizedBPM = max(0, min(1, (musicalState.bpm - 60) / 140)) // 60-200 → 0-1
        let excitementTarget = peakEnergy * 0.6 + normalizedBPM * 0.4
        state.excitement = ema(current: state.excitement, target: excitementTarget, alpha: excitementAlpha)

        // Valence: major key → higher, minor key → lower
        if musicalState.keyConfidence > 0.4 && musicalState.detectedKey != .unknown {
            let valenceTarget: Double = musicalState.detectedKey.isMajor ? 0.7 : 0.3
            state.valence = ema(current: state.valence, target: valenceTarget, alpha: valenceAlpha)
        }
        // If no confident key, valence drifts slowly toward neutral
        else {
            state.valence = ema(current: state.valence, target: 0.5, alpha: valenceAlpha * 0.1)
        }

        // Brightness: spectral centroid normalized (500Hz = dark, 5000Hz = bright)
        let normalizedCentroid = max(0, min(1, (musicalState.spectralCentroid - 500) / 4500))
        state.brightness = ema(current: state.brightness, target: normalizedCentroid, alpha: brightnessAlpha)

        // Chaos: spectral flatness
        state.chaos = ema(current: state.chaos, target: musicalState.spectralFlatness, alpha: chaosAlpha)

        state.peakEnergy = peakEnergy

        // Intensity: tracks peak envelope — asymmetric EMA (fast attack, slow decay)
        let intensityTau = peakEnergy > state.intensity ? 0.3 : 2.0
        let intensityAlpha = emaAlpha(deltaTime: deltaTime, timeConstant: intensityTau)
        state.intensity = ema(current: state.intensity, target: peakEnergy, alpha: intensityAlpha)

        // Energy trajectory (also based on peak envelope)
        updateTrajectory(energy: peakEnergy)

        // Bar counting
        if musicalState.isDownbeat {
            barCounter += 1
        }
    }

    private mutating func updateTrajectory(energy: Double) {
        energyHistory.append(energy)
        if energyHistory.count > Self.energyHistorySize {
            energyHistory.removeFirst()
        }

        guard energyHistory.count >= 40 else {
            state.energyTrajectory = .stable
            return
        }

        // Compare two adjacent recent windows — not beginning vs end.
        // "recent" = last 20 frames (~0.4s), "prior" = the 20 frames before that (~0.4s).
        let recent = energyHistory.suffix(20)
        let prior = energyHistory.suffix(40).prefix(20)
        let recentAvg = recent.reduce(0, +) / Double(recent.count)
        let priorAvg = prior.reduce(0, +) / Double(prior.count)
        let diff = recentAvg - priorAvg

        // Compute raw trajectory from the trend
        let rawTrajectory: EnergyTrajectory
        if diff > 0.05 {
            rawTrajectory = .building
        } else if diff < -0.05 {
            rawTrajectory = .declining
        } else if recentAvg > 0.55 {
            rawTrajectory = .sustaining
        } else {
            rawTrajectory = .stable
        }

        // Hysteresis: require consistent signal before committing to a new trajectory.
        if rawTrajectory == candidateTrajectory {
            candidateFrameCount += 1
        } else {
            candidateTrajectory = rawTrajectory
            candidateFrameCount = 1
        }

        let threshold: Int
        switch rawTrajectory {
        case .building, .sustaining:
            threshold = Self.debounceUp      // commit quickly to energy gains
        case .declining, .stable:
            threshold = Self.debounceDown     // slower to commit to energy loss
        }

        if candidateFrameCount >= threshold {
            state.energyTrajectory = candidateTrajectory
        }
    }

    private func ema(current: Double, target: Double, alpha: Double) -> Double {
        current + alpha * (target - current)
    }

    private func emaAlpha(deltaTime: Double, timeConstant: Double) -> Double {
        1.0 - exp(-deltaTime / timeConstant)
    }
}
