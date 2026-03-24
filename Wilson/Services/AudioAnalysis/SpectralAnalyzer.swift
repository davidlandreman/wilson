import Accelerate

/// Extracts spectral features from FFT magnitude data: band energies, centroid, flatness, flux, dominant frequency.
final class SpectralAnalyzer: @unchecked Sendable {
    struct Result {
        var spectralProfile = SpectralProfile()
        var centroid: Double = 0       // Hz
        var flatness: Double = 0       // 0 (tonal) – 1 (noise)
        var flux: Float = 0            // Spectral change from previous frame (broadband)
        var bassFlux: Float = 0        // Spectral flux for bass range only (60–250 Hz)
        var dominantFrequency: Double = 0
    }

    private let binCount: Int
    private let sampleRate: Double
    private let fftSize: Int

    /// Pre-computed center frequency for each bin.
    private let binFrequencies: [Float]

    /// Band boundary bin indices [start, end) for each of the 5 bands.
    private let bandRanges: [(start: Int, count: Int)]

    /// Previous frame magnitudes for flux computation.
    private var previousMagnitudes: [Float]

    /// Previous frame bass magnitudes for bass flux.
    private var previousBassMagnitudes: [Float]
    private let bassStart: Int
    private let bassCount: Int

    /// Scratch buffers.
    private var diffBuffer: [Float]

    init(fftSize: Int = 2048, sampleRate: Double = 48000) {
        self.fftSize = fftSize
        self.binCount = fftSize / 2
        self.sampleRate = sampleRate

        // Pre-compute bin center frequencies
        let binWidth = Float(sampleRate) / Float(fftSize)
        self.binFrequencies = (0..<fftSize / 2).map { Float($0) * binWidth }

        // Band boundaries in Hz → bin indices
        // Sub-bass: 20–60, Bass: 60–250, Mids: 250–2000, Highs: 2000–6000, Presence: 6000–20000
        let boundaries: [(low: Double, high: Double)] = [
            (20, 60), (60, 250), (250, 2000), (2000, 6000), (6000, 20000)
        ]
        self.bandRanges = boundaries.map { band in
            let startBin = max(1, Int(round(band.low * Double(fftSize) / sampleRate)))
            let endBin = min(fftSize / 2, Int(round(band.high * Double(fftSize) / sampleRate)))
            return (start: startBin, count: max(0, endBin - startBin))
        }

        // Bass range for bass-specific flux (band index 1 = 60–250 Hz)
        self.bassStart = self.bandRanges[1].start
        self.bassCount = self.bandRanges[1].count

        self.previousMagnitudes = [Float](repeating: 0, count: fftSize / 2)
        self.previousBassMagnitudes = [Float](repeating: 0, count: self.bandRanges[1].count)
        self.diffBuffer = [Float](repeating: 0, count: fftSize / 2)
    }

    /// Analyze the magnitude spectrum and return spectral features.
    func analyze(magnitudes: UnsafePointer<Float>) -> Result {
        var result = Result()

        // MARK: Band Energies
        let bandValues = bandRanges.map { range -> Double in
            guard range.count > 0 else { return 0 }
            var sumSq: Float = 0
            vDSP_svesq(magnitudes.advanced(by: range.start), 1, &sumSq, vDSP_Length(range.count))
            return Double(sqrtf(sumSq / Float(range.count)))
        }

        result.spectralProfile = SpectralProfile(
            subBass: bandValues[0],
            bass: bandValues[1],
            mids: bandValues[2],
            highs: bandValues[3],
            presence: bandValues[4]
        )

        // MARK: Spectral Centroid (weighted mean frequency)
        let n = vDSP_Length(binCount)
        var dotProduct: Float = 0
        vDSP_dotpr(binFrequencies, 1, magnitudes, 1, &dotProduct, n)
        var magSum: Float = 0
        vDSP_sve(magnitudes, 1, &magSum, n)
        result.centroid = magSum > 0 ? Double(dotProduct / magSum) : 0

        // MARK: Spectral Flatness (geometric mean / arithmetic mean)
        // Geometric mean via log domain: exp(mean(log(x)))
        // Use bins 1..binCount to avoid log(0) at DC
        let usableBins = binCount - 1
        if usableBins > 0 {
            var arithMean: Float = 0
            vDSP_meanv(magnitudes.advanced(by: 1), 1, &arithMean, vDSP_Length(usableBins))

            if arithMean > 0 {
                // Clamp magnitudes to avoid log(0)
                var logSum: Float = 0
                for i in 1..<binCount {
                    let val = max(magnitudes[i], 1e-10)
                    logSum += logf(val)
                }
                let logMean = logSum / Float(usableBins)
                let geoMean = expf(logMean)
                result.flatness = Double(min(geoMean / arithMean, 1.0))
            }
        }

        // MARK: Dominant Frequency
        var maxVal: Float = 0
        var maxIdx: vDSP_Length = 0
        vDSP_maxvi(magnitudes, 1, &maxVal, &maxIdx, n)
        result.dominantFrequency = Double(maxIdx) * sampleRate / Double(fftSize)

        // MARK: Spectral Flux (half-wave rectified difference from previous frame)
        vDSP_vsub(previousMagnitudes, 1, magnitudes, 1, &diffBuffer, 1, n)
        // Half-wave rectify: zero out negatives
        var zero: Float = 0
        vDSP_vthres(diffBuffer, 1, &zero, &diffBuffer, 1, n)
        vDSP_sve(diffBuffer, 1, &result.flux, n)

        // MARK: Bass Flux (60–250 Hz only, for beat tracking)
        if bassCount > 0 {
            var bassDiff = [Float](repeating: 0, count: bassCount)
            vDSP_vsub(previousBassMagnitudes, 1, magnitudes.advanced(by: bassStart), 1, &bassDiff, 1, vDSP_Length(bassCount))
            var bzero: Float = 0
            vDSP_vthres(bassDiff, 1, &bzero, &bassDiff, 1, vDSP_Length(bassCount))
            vDSP_sve(bassDiff, 1, &result.bassFlux, vDSP_Length(bassCount))

            previousBassMagnitudes.withUnsafeMutableBufferPointer { dst in
                dst.baseAddress!.update(from: magnitudes.advanced(by: bassStart), count: bassCount)
            }
        }

        // Store current magnitudes for next frame's broadband flux
        previousMagnitudes.withUnsafeMutableBufferPointer { dst in
            dst.baseAddress!.update(from: magnitudes, count: binCount)
        }

        return result
    }
}
