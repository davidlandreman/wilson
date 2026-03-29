import Accelerate

/// Orchestrates all DSP components on the audio queue.
/// Chains: RingBuffer → FFT → Spectral/Energy/Onset/Beat/Chromagram → MusicalState snapshot.
final class DSPPipeline: @unchecked Sendable {
    private let fftSize: Int
    private let hopSize: Int
    private let sampleRate: Double
    private let waveformSize: Int

    // DSP components
    private let ringBuffer: RingBuffer
    private let fftEngine: FFTEngine
    private let spectralAnalyzer: SpectralAnalyzer
    private var energyAnalyzer: EnergyAnalyzer
    private var energyNormalizer: AdaptiveEnergyNormalizer
    private let onsetDetector: OnsetDetector
    private let beatTracker: BeatTracker
    private let chromagramAnalyzer: ChromagramAnalyzer

    // Pre-allocated work buffers (avoid allocation on audio thread)
    private var fftInputBuffer: [Float]
    private var magnitudeBuffer: [Float]
    private var waveformBuffer: [Float]

    // Smoothed band energies for stable display
    private var smoothedBands = SpectralProfile()
    private let bandSmoothing: Double = 0.3

    init(fftSize: Int = 2048, hopSize: Int = 1024, sampleRate: Double = 48000) {
        self.fftSize = fftSize
        self.hopSize = hopSize
        self.sampleRate = sampleRate
        self.waveformSize = Int(sampleRate * 0.05) // ~50ms

        let analysisRate = sampleRate / Double(hopSize) // ~47 Hz

        self.ringBuffer = RingBuffer(capacity: fftSize * 2, hopSize: hopSize)
        self.fftEngine = FFTEngine(fftSize: fftSize)
        self.spectralAnalyzer = SpectralAnalyzer(fftSize: fftSize, sampleRate: sampleRate)
        self.energyAnalyzer = EnergyAnalyzer()
        self.energyNormalizer = AdaptiveEnergyNormalizer(analysisRate: analysisRate)
        self.onsetDetector = OnsetDetector()
        self.beatTracker = BeatTracker(analysisRate: analysisRate)
        self.chromagramAnalyzer = ChromagramAnalyzer(
            fftSize: fftSize, sampleRate: sampleRate, analysisRate: analysisRate
        )

        self.fftInputBuffer = [Float](repeating: 0, count: fftSize)
        self.magnitudeBuffer = [Float](repeating: 0, count: fftSize / 2)
        self.waveformBuffer = [Float](repeating: 0, count: waveformSize)
    }

    /// Process incoming audio samples. Returns a MusicalState snapshot when a new
    /// analysis frame is ready, or nil if more samples are needed.
    func processBuffer(_ samples: UnsafeBufferPointer<Float>) -> MusicalState? {
        ringBuffer.write(samples)

        var latestState: MusicalState?

        // Process all available hops
        while ringBuffer.isHopReady && ringBuffer.availableSamples >= fftSize {
            latestState = analyzeFrame(samples: samples)
            ringBuffer.consumeHop()
        }

        return latestState
    }

    private func analyzeFrame(samples: UnsafeBufferPointer<Float>) -> MusicalState {
        var state = MusicalState()

        // Read FFT window from ring buffer
        fftInputBuffer.withUnsafeMutableBufferPointer { buf in
            ringBuffer.read(count: fftSize, into: buf.baseAddress!)
        }

        // FFT → magnitude spectrum
        fftInputBuffer.withUnsafeBufferPointer { input in
            magnitudeBuffer.withUnsafeMutableBufferPointer { output in
                fftEngine.process(input: input.baseAddress!, magnitudes: output.baseAddress!)
            }
        }

        // Spectral analysis
        let spectral = magnitudeBuffer.withUnsafeBufferPointer { buf in
            spectralAnalyzer.analyze(magnitudes: buf.baseAddress!)
        }

        // Smooth band energies
        smoothedBands.subBass = bandSmoothing * spectral.spectralProfile.subBass + (1 - bandSmoothing) * smoothedBands.subBass
        smoothedBands.bass = bandSmoothing * spectral.spectralProfile.bass + (1 - bandSmoothing) * smoothedBands.bass
        smoothedBands.mids = bandSmoothing * spectral.spectralProfile.mids + (1 - bandSmoothing) * smoothedBands.mids
        smoothedBands.highs = bandSmoothing * spectral.spectralProfile.highs + (1 - bandSmoothing) * smoothedBands.highs
        smoothedBands.presence = bandSmoothing * spectral.spectralProfile.presence + (1 - bandSmoothing) * smoothedBands.presence

        state.spectralProfile = smoothedBands
        state.spectralCentroid = spectral.centroid
        state.spectralFlatness = spectral.flatness
        state.dominantFrequency = spectral.dominantFrequency

        // Energy analysis (from most recent raw samples, not windowed)
        let energy = fftInputBuffer.withUnsafeBufferPointer { buf in
            energyAnalyzer.analyze(buf.baseAddress!, count: fftSize)
        }
        state.rawEnergy = Double(energy.rms)
        state.energy = energyNormalizer.normalize(energy.rms)
        state.normalizationCeiling = energyNormalizer.currentCeiling
        state.peakLevel = Double(energy.peak)
        state.crestFactor = Double(energy.crestFactor)
        state.isSilent = energy.isSilent

        // Onset detection
        let onset = onsetDetector.detect(flux: spectral.flux)
        state.isOnset = onset.isOnset
        state.onsetStrength = onset.strength

        // Beat tracking — feed bass-weighted flux (continuous signal) for autocorrelation,
        // onset flag for phase correction, silence flag for inertia
        let beatFlux = 0.6 * spectral.bassFlux + 0.4 * spectral.flux
        let beat = beatTracker.update(flux: beatFlux, isOnset: onset.isOnset, isSilent: energy.isSilent)
        state.bpm = beat.bpm
        state.bpmConfidence = beat.bpmConfidence
        state.beatPhase = beat.beatPhase
        state.beatPosition = beat.beatPosition
        state.isBeat = beat.isBeat
        state.isDownbeat = beat.isDownbeat

        // Chromagram + key detection
        let chroma = magnitudeBuffer.withUnsafeBufferPointer { buf in
            chromagramAnalyzer.analyze(magnitudes: buf.baseAddress!)
        }
        state.chromagram = chroma.chromagram
        state.detectedKey = chroma.detectedKey
        state.keyConfidence = chroma.keyConfidence

        // Visualization data
        state.magnitudeSpectrum = magnitudeBuffer

        waveformBuffer.withUnsafeMutableBufferPointer { buf in
            let available = min(waveformSize, ringBuffer.availableSamples)
            ringBuffer.read(count: available, into: buf.baseAddress!)
        }
        state.waveformBuffer = waveformBuffer

        return state
    }
}
