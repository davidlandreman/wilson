import Accelerate

/// Normalizes raw RMS energy from system audio capture to a 0.0–1.0 range
/// using sliding-window percentile tracking. Adapts automatically to any
/// volume level — loud EDM drops and quiet ambient both fill the 0–1 range.
struct AdaptiveEnergyNormalizer: @unchecked Sendable {
    // MARK: - Configuration

    private let windowSize: Int
    private let targetCeiling: Double
    private let defaultCeiling: Double
    private let floorThreshold: Double
    private let decayPerFrame: Double

    // MARK: - State

    /// Circular buffer of recent raw RMS values.
    private var buffer: [Float]
    private var writeIndex: Int = 0
    private var count: Int = 0

    /// Current reference ceiling derived from the window's 95th percentile.
    private(set) var currentCeiling: Double

    /// Scratch buffer for percentile sort (avoids allocation on audio thread).
    private var sortBuffer: [Float]

    /// - Parameters:
    ///   - analysisRate: Frames per second (~47 Hz).
    ///   - windowSeconds: How much history to track (default 12s ≈ one musical phrase).
    ///   - targetCeiling: The 95th-percentile peak maps to this output value.
    ///   - defaultCeiling: Cold-start assumption for the ceiling before data fills.
    ///   - floorThreshold: Raw RMS below this is treated as silence (output 0).
    ///   - silenceDecaySeconds: Half-life for ceiling decay during prolonged silence.
    init(
        analysisRate: Double = 47.0,
        windowSeconds: Double = 12.0,
        targetCeiling: Double = 0.85,
        defaultCeiling: Double = 0.15,
        floorThreshold: Double = 0.001,
        silenceDecaySeconds: Double = 3.0
    ) {
        let size = max(1, Int(analysisRate * windowSeconds))
        self.windowSize = size
        self.targetCeiling = targetCeiling
        self.defaultCeiling = defaultCeiling
        self.floorThreshold = floorThreshold
        // Per-frame decay factor: solve 0.5 = (1-d)^(rate*halfLife)
        self.decayPerFrame = 1.0 - pow(0.5, 1.0 / (analysisRate * silenceDecaySeconds))

        self.buffer = [Float](repeating: 0, count: size)
        self.sortBuffer = [Float](repeating: 0, count: size)
        self.currentCeiling = defaultCeiling
    }

    /// Normalize a raw RMS value to the 0.0–1.0 range.
    mutating func normalize(_ rawRMS: Float) -> Double {
        let raw = Double(rawRMS)

        // Silence passthrough — zero stays zero.
        guard raw > floorThreshold else { return 0 }

        // Record in circular buffer
        buffer[writeIndex] = rawRMS
        writeIndex = (writeIndex + 1) % windowSize
        count = min(count + 1, windowSize)

        // Compute 95th percentile of the window
        let n = count
        for i in 0..<n {
            sortBuffer[i] = buffer[i]
        }
        vDSP_vsort(&sortBuffer, vDSP_Length(n), 1) // ascending
        let p95Index = min(n - 1, Int(Double(n) * 0.95))
        let observedCeiling = Double(sortBuffer[p95Index])

        // Asymmetric ceiling tracking:
        //   Fast attack — if louder material arrives, jump most of the way immediately.
        //   Slow decay — ceiling drifts toward the observed 95th percentile, preserving
        //   relative dynamics during breakdowns (the 12s window itself provides stability).
        if observedCeiling > currentCeiling {
            currentCeiling = currentCeiling + 0.8 * (observedCeiling - currentCeiling)
        } else if count >= windowSize / 2 {
            currentCeiling += decayPerFrame * (observedCeiling - currentCeiling)
            currentCeiling = max(currentCeiling, defaultCeiling * 0.5)
        }

        // Enforce minimum ceiling to avoid division by near-zero
        let effectiveCeiling = max(currentCeiling, 0.005)

        // Linear mapping: raw / ceiling → 0..targetCeiling
        let normalized = (raw / effectiveCeiling) * targetCeiling

        // Soft-clip: linear up to targetCeiling, tanh curve above → approaches 1.0
        return softClip(normalized)
    }

    private func softClip(_ value: Double) -> Double {
        if value <= targetCeiling { return value }
        let excess = value - targetCeiling
        let headroom = 1.0 - targetCeiling
        return targetCeiling + headroom * tanh(excess / headroom)
    }
}
