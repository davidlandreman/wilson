import Accelerate

/// Estimates BPM via autocorrelation of spectral flux, tracks beat phase with a
/// phase-locked clock, and maintains bar position. Includes inertia ("flywheel")
/// to hold tempo through brief silence and transitions.
final class BeatTracker: @unchecked Sendable {
    struct Result {
        var bpm: Double = 0
        var bpmConfidence: Double = 0
        var beatPhase: Double = 0       // 0.0→1.0 within current beat
        var beatPosition: Double = 0    // 0.0→4.0 within bar
        var isBeat: Bool = false
        var isDownbeat: Bool = false
    }

    // Configuration
    private let analysisRate: Double     // Hz (frames per second from DSP pipeline)
    private let minBPM: Double = 60
    private let maxBPM: Double = 200
    private let preferredBPMRange = 90.0...160.0

    // Flux history for autocorrelation (continuous signal, not thresholded)
    private let historySize: Int         // ~6 seconds of flux data
    private var fluxHistory: [Float]
    private var historyWritePos: Int = 0
    private var historyCount: Int = 0

    // Autocorrelation buffers
    private let acfSize: Int             // Next power of 2 >= historySize * 2
    private let log2Acf: vDSP_Length
    private let acfSetup: FFTSetup
    private var acfReal: [Float]
    private var acfImag: [Float]
    private var acfInput: [Float]
    private var acfResult: [Float]       // Full-size (acfSize), properly unpacked

    // BPM estimation state
    private var currentBPM: Double = 0
    private var currentConfidence: Double = 0
    private var framesUntilNextACF: Int = 0
    private let acfInterval: Int         // Frames between autocorrelation runs

    // Inertia / flywheel
    private let confidenceDecay: Double = 0.995  // Per-frame decay (~47Hz → 50% in ~3 seconds)
    private let switchMargin: Double = 0.2       // New BPM must exceed current confidence by this
    private let matchTolerance: Double = 0.04    // 4% BPM tolerance for "same tempo"
    private var isSilent: Bool = false

    // Phase-locked beat clock
    private var beatPhase: Double = 0
    private var barBeatCount: Int = 0    // 0–3 for 4/4 time
    private let phaseCorrection: Double = 0.2

    init(analysisRate: Double) {
        self.analysisRate = analysisRate

        // ~6 seconds of flux history (longer window for better low-BPM detection)
        self.historySize = Int(analysisRate * 6)
        self.fluxHistory = [Float](repeating: 0, count: historySize)

        // Autocorrelation FFT: next power of 2 >= 2 * historySize
        var acf = 1
        while acf < historySize * 2 { acf *= 2 }
        self.acfSize = acf
        self.log2Acf = vDSP_Length(log2(Double(acf)))
        self.acfSetup = vDSP_create_fftsetup(log2Acf, FFTRadix(kFFTRadix2))!
        self.acfReal = [Float](repeating: 0, count: acf / 2)
        self.acfImag = [Float](repeating: 0, count: acf / 2)
        self.acfInput = [Float](repeating: 0, count: acf)
        self.acfResult = [Float](repeating: 0, count: acf)  // Full size for proper unpacking

        // Run autocorrelation every ~500ms
        self.acfInterval = max(1, Int(analysisRate * 0.5))
        self.framesUntilNextACF = 10 // Start quickly
    }

    deinit {
        vDSP_destroy_fftsetup(acfSetup)
    }

    /// Update the beat tracker with the latest spectral flux and onset flag.
    /// - Parameters:
    ///   - flux: Raw spectral flux (continuous, non-zero every frame). Bass-weighted preferred.
    ///   - isOnset: Binary onset detection flag (for phase correction only).
    ///   - isSilent: Whether the audio is currently silent.
    func update(flux: Float, isOnset: Bool, isSilent: Bool) -> Result {
        self.isSilent = isSilent

        // Record flux in history (continuous signal for autocorrelation)
        fluxHistory[historyWritePos] = flux
        historyWritePos = (historyWritePos + 1) % historySize
        historyCount = min(historyCount + 1, historySize)

        // Apply confidence decay (flywheel slowing down)
        if !isSilent {
            currentConfidence *= confidenceDecay
        }
        // During silence: freeze confidence (don't lose tempo during song breaks)

        // Periodically re-estimate BPM via autocorrelation
        framesUntilNextACF -= 1
        if framesUntilNextACF <= 0 && historyCount >= Int(analysisRate * 2) {
            estimateBPM()
            framesUntilNextACF = acfInterval
        }

        // Advance phase-locked beat clock
        return advanceBeatClock(isOnset: isOnset)
    }

    // MARK: - BPM Estimation via Autocorrelation

    private func estimateBPM() {
        // Linearize flux history into acfInput (zero-padded)
        acfInput.withUnsafeMutableBufferPointer { buf in
            buf.baseAddress!.update(repeating: 0, count: acfSize)
        }
        let count = historyCount
        let readStart = ((historyWritePos - count) % historySize + historySize) % historySize
        for i in 0..<count {
            acfInput[i] = fluxHistory[(readStart + i) % historySize]
        }

        // Autocorrelation via FFT: R(τ) = IFFT(|FFT(x)|²)
        let half = acfSize / 2

        // Pack input for real FFT (even→real, odd→imag)
        for i in 0..<half {
            acfReal[i] = acfInput[2 * i]
            acfImag[i] = acfInput[2 * i + 1]
        }

        acfReal.withUnsafeMutableBufferPointer { realBuf in
            acfImag.withUnsafeMutableBufferPointer { imagBuf in
                var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)

                // Forward FFT
                vDSP_fft_zrip(acfSetup, &split, 1, log2Acf, FFTDirection(kFFTDirection_Forward))

                // Power spectrum: |X|² = re² + im²
                vDSP_zvmags(&split, 1, realBuf.baseAddress!, 1, vDSP_Length(half))
                // Zero imaginary for inverse FFT
                imagBuf.baseAddress!.update(repeating: 0, count: half)

                // Inverse FFT → autocorrelation
                vDSP_fft_zrip(acfSetup, &split, 1, log2Acf, FFTDirection(kFFTDirection_Inverse))

                // CRITICAL: Properly unpack split complex format back to interleaved
                // After inverse zrip, realp[k] = time[2k], imagp[k] = time[2k+1]
                for i in 0..<half {
                    self.acfResult[2 * i]     = realBuf[i]
                    self.acfResult[2 * i + 1] = imagBuf[i]
                }
            }
        }

        // Normalize autocorrelation by lag-0 value (energy)
        let lag0 = acfResult[0]
        guard lag0 > 0 else { return }
        for i in 0..<acfSize {
            acfResult[i] /= lag0
        }

        // Comb filter bank: score every candidate BPM by summing autocorrelation
        // at all harmonic lags. True tempo scores highest because its harmonics
        // align with the most peaks — naturally resolves octave and metric ambiguity.
        let maxUsableLag = acfSize / 2
        let result = combFilterBankScore(maxUsableLag: maxUsableLag)
        guard result.bpm > 0 else { return }

        // Update BPM with inertia
        updateBPMWithInertia(result.bpm, confidence: result.confidence)
    }

    /// Comb filter bank: test every candidate BPM at 0.5 BPM resolution.
    /// For each candidate, sum the autocorrelation at lag, 2×lag, 3×lag, ...
    /// The true tempo naturally scores highest because all its harmonics align.
    /// This resolves octave errors, metric ambiguity (90 vs 136 vs 180), etc.
    private func combFilterBankScore(maxUsableLag: Int) -> (bpm: Double, confidence: Double) {
        // Test BPMs at 0.5 resolution (280 candidates for 60–200 range)
        let bpmStep = 0.5
        let candidateCount = Int((maxBPM - minBPM) / bpmStep) + 1
        let maxHarmonics = 10

        var bestBPM: Double = 0
        var bestScore: Double = 0
        var secondBestScore: Double = 0

        for ci in 0..<candidateCount {
            let bpm = minBPM + Double(ci) * bpmStep
            let fundamentalLag = analysisRate * 60.0 / bpm

            // Sum autocorrelation at all harmonic lags
            var score: Double = 0
            for k in 1...maxHarmonics {
                let harmonicLag = Int(round(fundamentalLag * Double(k)))
                guard harmonicLag > 0 && harmonicLag < maxUsableLag else { break }
                // Weight: 1/k so fundamental matters most, higher harmonics are confirming
                let weight = 1.0 / Double(k)
                score += weight * Double(max(0, acfResult[harmonicLag]))
            }

            // Mild preference for common tempo range
            if preferredBPMRange.contains(bpm) {
                score *= 1.05
            }

            if score > bestScore {
                secondBestScore = bestScore
                bestScore = score
                bestBPM = bpm
            } else if score > secondBestScore && abs(bpm - bestBPM) > 5.0 {
                // Only count as second-best if it's not a neighbor of the best
                secondBestScore = score
            }
        }

        guard bestScore > 0 else { return (0, 0) }

        // Confidence: how much the winner stands out from the runner-up
        let prominence = secondBestScore > 0
            ? (bestScore - secondBestScore) / bestScore
            : 0.9

        // Scale: strong prominence + strong absolute peak → high confidence
        let peakStrength = min(Double(acfResult[Int(round(analysisRate * 60.0 / bestBPM))]), 1.0)
        let confidence = min(0.5 * prominence + 0.5 * peakStrength, 1.0)

        return (bestBPM, confidence)
    }

    // MARK: - BPM Inertia ("Flywheel")

    private func updateBPMWithInertia(_ estimatedBPM: Double, confidence: Double) {
        if currentBPM == 0 {
            // No existing BPM — accept immediately
            currentBPM = estimatedBPM
            currentConfidence = confidence
            return
        }

        let isMatch = abs(estimatedBPM - currentBPM) / currentBPM < matchTolerance

        if isMatch {
            // Confirms current BPM — boost confidence (re-lock)
            currentBPM = 0.95 * currentBPM + 0.05 * estimatedBPM // Gentle refinement
            currentConfidence = max(currentConfidence, confidence) // Boost, don't lower
        } else {
            // Different BPM — must exceed current confidence + margin to switch
            if confidence > currentConfidence + switchMargin {
                currentBPM = estimatedBPM
                currentConfidence = confidence
            }
            // Otherwise: ignore the new estimate (flywheel holds)
        }
    }

    // MARK: - Phase-Locked Beat Clock

    private func advanceBeatClock(isOnset: Bool) -> Result {
        guard currentBPM > 0 else {
            return Result()
        }

        let hopDuration = 1.0 / analysisRate
        let phaseIncrement = (currentBPM / 60.0) * hopDuration

        beatPhase += phaseIncrement

        var isBeat = false
        var isDownbeat = false

        // Check for beat boundary crossing
        if beatPhase >= 1.0 {
            beatPhase -= 1.0
            isBeat = true

            barBeatCount = (barBeatCount + 1) % 4
            if barBeatCount == 0 {
                isDownbeat = true
            }
        }

        // Phase correction: nudge toward detected onsets near expected beats
        if isOnset && !isSilent {
            let distanceToNextBeat = 1.0 - beatPhase
            let distanceToPrevBeat = beatPhase

            if distanceToNextBeat < 0.2 {
                beatPhase += distanceToNextBeat * phaseCorrection
                if beatPhase >= 1.0 {
                    beatPhase -= 1.0
                    isBeat = true
                    barBeatCount = (barBeatCount + 1) % 4
                    if barBeatCount == 0 { isDownbeat = true }
                }
            } else if distanceToPrevBeat < 0.2 {
                beatPhase -= distanceToPrevBeat * phaseCorrection
                if beatPhase < 0 { beatPhase += 1.0 }
            }
        }

        let beatPosition = Double(barBeatCount) + beatPhase

        return Result(
            bpm: currentBPM,
            bpmConfidence: currentConfidence,
            beatPhase: beatPhase,
            beatPosition: beatPosition,
            isBeat: isBeat,
            isDownbeat: isDownbeat
        )
    }
}

// MARK: - Helpers

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
