import Accelerate

/// Computes RMS energy, peak level, crest factor, and silence detection from time-domain samples.
struct EnergyAnalyzer: @unchecked Sendable {
    struct Result {
        var rms: Float = 0
        var peak: Float = 0
        var crestFactor: Float = 0
        var isSilent: Bool = true
    }

    private var silentFrameCount: Int = 0
    private let silenceThreshold: Float = 0.001 // ~-60 dBFS
    private let silenceFramesRequired: Int = 5   // ~100ms at 47 Hz analysis rate

    /// Analyze time-domain samples and return energy metrics.
    mutating func analyze(_ samples: UnsafePointer<Float>, count: Int) -> Result {
        guard count > 0 else { return Result() }
        let n = vDSP_Length(count)

        // RMS energy
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, n)

        // Peak absolute amplitude
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, n)

        // Crest factor: peak / RMS, normalized to 0–1 (reference max ~15)
        let rawCrest = rms > 0 ? peak / rms : 0
        let normalizedCrest = min(rawCrest / 15.0, 1.0)

        // Silence detection with hysteresis
        if rms < silenceThreshold {
            silentFrameCount += 1
        } else {
            silentFrameCount = 0
        }

        return Result(
            rms: rms,
            peak: peak,
            crestFactor: normalizedCrest,
            isSilent: silentFrameCount >= silenceFramesRequired
        )
    }
}
