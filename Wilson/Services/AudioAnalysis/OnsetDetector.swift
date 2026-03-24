import Accelerate

/// Detects transient onsets (drum hits, note attacks) using spectral flux with an adaptive threshold.
final class OnsetDetector: @unchecked Sendable {
    struct Result {
        var isOnset: Bool = false
        var strength: Double = 0   // 0–1, how far above threshold
    }

    private let medianWindowSize: Int
    private let minimumIntervalFrames: Int
    private let sensitivity: Float

    /// Circular buffer of recent spectral flux values for adaptive threshold.
    private var fluxHistory: [Float]
    private var fluxWritePos: Int = 0
    private var fluxCount: Int = 0

    /// For peak-picking: previous frame's flux.
    private var previousFlux: Float = 0

    /// Frames since last detected onset.
    private var framesSinceOnset: Int = 100

    /// Scratch buffer for median computation.
    private var sortBuffer: [Float]

    /// - Parameters:
    ///   - medianWindow: Number of recent flux values for adaptive threshold (~0.5s).
    ///   - minimumInterval: Minimum frames between onsets (~50ms).
    ///   - sensitivity: Multiplier on median for threshold. Lower = more sensitive.
    init(medianWindow: Int = 23, minimumInterval: Int = 3, sensitivity: Float = 1.5) {
        self.medianWindowSize = medianWindow
        self.minimumIntervalFrames = minimumInterval
        self.sensitivity = sensitivity
        self.fluxHistory = [Float](repeating: 0, count: medianWindow)
        self.sortBuffer = [Float](repeating: 0, count: medianWindow)
    }

    /// Detect onset from the current frame's spectral flux.
    func detect(flux: Float) -> Result {
        // Store flux in history
        fluxHistory[fluxWritePos] = flux
        fluxWritePos = (fluxWritePos + 1) % medianWindowSize
        fluxCount = min(fluxCount + 1, medianWindowSize)
        framesSinceOnset += 1

        // Compute adaptive threshold via median
        let count = fluxCount
        for i in 0..<count {
            sortBuffer[i] = fluxHistory[i]
        }
        let sortCount = vDSP_Length(count)
        vDSP_vsort(&sortBuffer, sortCount, 1) // ascending sort
        let median = sortBuffer[count / 2]
        let threshold = median * sensitivity + 0.001 // small offset to avoid zero threshold

        // Peak-picking: current flux must exceed threshold and be a local peak
        let isOnset = flux > threshold
            && flux >= previousFlux
            && framesSinceOnset >= minimumIntervalFrames

        let strength: Double
        if isOnset {
            framesSinceOnset = 0
            strength = min(Double((flux - threshold) / max(threshold, 0.001)), 1.0)
        } else {
            strength = 0
        }

        previousFlux = flux

        return Result(isOnset: isOnset, strength: strength)
    }
}
