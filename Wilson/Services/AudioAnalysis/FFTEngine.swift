import Accelerate

/// Performs forward FFT on windowed audio samples and produces a magnitude spectrum.
/// Uses vDSP for hardware-accelerated computation.
final class FFTEngine: @unchecked Sendable {
    let fftSize: Int
    let binCount: Int

    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private var window: [Float]
    private var windowed: [Float]
    private var realPart: [Float]
    private var imagPart: [Float]

    init(fftSize: Int = 2048) {
        precondition(fftSize > 0 && (fftSize & (fftSize - 1)) == 0, "FFT size must be a power of 2")
        self.fftSize = fftSize
        self.binCount = fftSize / 2
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!

        self.window = [Float](repeating: 0, count: fftSize)
        self.windowed = [Float](repeating: 0, count: fftSize)
        self.realPart = [Float](repeating: 0, count: fftSize / 2)
        self.imagPart = [Float](repeating: 0, count: fftSize / 2)

        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Process `fftSize` samples and write `binCount` magnitude values to `output`.
    /// Both pointers must have sufficient capacity.
    func process(input: UnsafePointer<Float>, magnitudes output: UnsafeMutablePointer<Float>) {
        // 1. Apply Hann window
        vDSP_vmul(input, 1, &window, 1, &windowed, 1, vDSP_Length(fftSize))

        // 2. Pack into split complex (even → real, odd → imaginary)
        let half = binCount
        for i in 0..<half {
            realPart[i] = windowed[2 * i]
            imagPart[i] = windowed[2 * i + 1]
        }

        // 3. Forward real-to-complex FFT in-place, then compute magnitudes
        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                var split = DSPSplitComplex(
                    realp: realBuf.baseAddress!,
                    imagp: imagBuf.baseAddress!
                )
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))

                // Magnitude: sqrt(re^2 + im^2) for each bin
                // Note: bin 0 packs DC in realp[0] and Nyquist in imagp[0].
                // zvabs will conflate them, which is acceptable — neither is useful for music analysis.
                vDSP_zvabs(&split, 1, output, 1, vDSP_Length(half))
            }
        }

        // 4. Normalize: scale by 1/binCount for consistent amplitude representation
        var scale = 1.0 / Float(half)
        vDSP_vsmul(output, 1, &scale, output, 1, vDSP_Length(half))
    }

    /// Frequency in Hz for a given FFT bin index.
    func frequency(forBin bin: Int, sampleRate: Double) -> Double {
        Double(bin) * sampleRate / Double(fftSize)
    }

    /// FFT bin index for a given frequency in Hz.
    func bin(forFrequency freq: Double, sampleRate: Double) -> Int {
        Int(round(freq * Double(fftSize) / sampleRate))
    }
}
