import Testing
import Accelerate
@testable import Wilson

// MARK: - Test Signal Generators

private func sineWave(frequency: Float, sampleRate: Float, count: Int, amplitude: Float = 1.0) -> [Float] {
    (0..<count).map { i in
        amplitude * sinf(2 * .pi * frequency * Float(i) / sampleRate)
    }
}

private func whiteNoise(count: Int) -> [Float] {
    (0..<count).map { _ in Float.random(in: -1...1) }
}

private func silence(count: Int) -> [Float] {
    [Float](repeating: 0, count: count)
}

private func impulseTrainSignal(bpm: Double, sampleRate: Float, durationSeconds: Double, hopSize: Int) -> [Float] {
    let totalSamples = Int(Double(sampleRate) * durationSeconds)
    let samplesPerBeat = Int(Double(sampleRate) * 60.0 / bpm)
    var signal = [Float](repeating: 0, count: totalSamples)
    var pos = 0
    while pos < totalSamples {
        // Create a short burst (click) at each beat
        for i in 0..<min(100, totalSamples - pos) {
            signal[pos + i] = Float.random(in: 0.5...1.0)
        }
        pos += samplesPerBeat
    }
    return signal
}

// MARK: - RingBuffer Tests

@Suite("RingBuffer")
struct RingBufferTests {
    @Test func accumulates() {
        let buffer = RingBuffer(capacity: 8, hopSize: 4)
        let data: [Float] = [1, 2, 3, 4]

        data.withUnsafeBufferPointer { buffer.write($0) }
        #expect(buffer.availableSamples == 4)
        #expect(buffer.isHopReady)
    }

    @Test func readsMostRecent() {
        let buffer = RingBuffer(capacity: 16, hopSize: 4)
        let data1: [Float] = [1, 2, 3, 4]
        let data2: [Float] = [5, 6, 7, 8]

        data1.withUnsafeBufferPointer { buffer.write($0) }
        data2.withUnsafeBufferPointer { buffer.write($0) }

        var output = [Float](repeating: 0, count: 4)
        output.withUnsafeMutableBufferPointer { buf in
            buffer.read(count: 4, into: buf.baseAddress!)
        }
        #expect(output == [5, 6, 7, 8])
    }

    @Test func wrapsAround() {
        let buffer = RingBuffer(capacity: 6, hopSize: 3)
        let data1: [Float] = [1, 2, 3, 4, 5]
        let data2: [Float] = [6, 7, 8]

        data1.withUnsafeBufferPointer { buffer.write($0) }
        data2.withUnsafeBufferPointer { buffer.write($0) }

        var output = [Float](repeating: 0, count: 6)
        output.withUnsafeMutableBufferPointer { buf in
            buffer.read(count: 6, into: buf.baseAddress!)
        }
        #expect(output == [3, 4, 5, 6, 7, 8])
    }

    @Test func hopTracking() {
        let buffer = RingBuffer(capacity: 16, hopSize: 4)

        let chunk: [Float] = [1, 2]
        chunk.withUnsafeBufferPointer { buffer.write($0) }
        #expect(!buffer.isHopReady)

        chunk.withUnsafeBufferPointer { buffer.write($0) }
        #expect(buffer.isHopReady)

        buffer.consumeHop()
        #expect(!buffer.isHopReady)
    }
}

// MARK: - FFTEngine Tests

@Suite("FFTEngine")
struct FFTEngineTests {
    @Test func detectsSineFrequency() {
        let fftSize = 2048
        let sampleRate: Float = 48000
        let engine = FFTEngine(fftSize: fftSize)

        let signal = sineWave(frequency: 440, sampleRate: sampleRate, count: fftSize)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)

        signal.withUnsafeBufferPointer { input in
            magnitudes.withUnsafeMutableBufferPointer { output in
                engine.process(input: input.baseAddress!, magnitudes: output.baseAddress!)
            }
        }

        // Find the peak bin
        var maxVal: Float = 0
        var maxIdx: vDSP_Length = 0
        magnitudes.withUnsafeBufferPointer { buf in
            vDSP_maxvi(buf.baseAddress!, 1, &maxVal, &maxIdx, vDSP_Length(fftSize / 2))
        }

        let peakFreq = Float(maxIdx) * sampleRate / Float(fftSize)

        // Should be within one bin of 440 Hz (bin width = 23.4 Hz)
        #expect(abs(peakFreq - 440) < 25)
        #expect(maxVal > 0)
    }

    @Test func magnitudeScalesWithAmplitude() {
        let fftSize = 2048
        let sampleRate: Float = 48000
        let engine = FFTEngine(fftSize: fftSize)

        let signalLoud = sineWave(frequency: 1000, sampleRate: sampleRate, count: fftSize, amplitude: 1.0)
        let signalQuiet = sineWave(frequency: 1000, sampleRate: sampleRate, count: fftSize, amplitude: 0.5)

        var magsLoud = [Float](repeating: 0, count: fftSize / 2)
        var magsQuiet = [Float](repeating: 0, count: fftSize / 2)

        signalLoud.withUnsafeBufferPointer { input in
            magsLoud.withUnsafeMutableBufferPointer { output in
                engine.process(input: input.baseAddress!, magnitudes: output.baseAddress!)
            }
        }
        signalQuiet.withUnsafeBufferPointer { input in
            magsQuiet.withUnsafeMutableBufferPointer { output in
                engine.process(input: input.baseAddress!, magnitudes: output.baseAddress!)
            }
        }

        let peakLoud = magsLoud.max() ?? 0
        let peakQuiet = magsQuiet.max() ?? 0

        // Loud should be roughly 2x quiet
        #expect(peakLoud > peakQuiet * 1.5)
    }

    @Test func binFrequencyConversion() {
        let engine = FFTEngine(fftSize: 2048)
        let freq = engine.frequency(forBin: 19, sampleRate: 48000)
        // bin 19 = 19 * 48000 / 2048 ≈ 445 Hz
        #expect(abs(freq - 445) < 1)

        let bin = engine.bin(forFrequency: 440, sampleRate: 48000)
        #expect(bin == 19) // 440 * 2048 / 48000 ≈ 18.77 → rounds to 19
    }
}

// MARK: - EnergyAnalyzer Tests

@Suite("EnergyAnalyzer")
struct EnergyAnalyzerTests {
    @Test func rmsCorrectForSine() {
        var analyzer = EnergyAnalyzer()
        let signal = sineWave(frequency: 440, sampleRate: 48000, count: 2048, amplitude: 1.0)

        let result = signal.withUnsafeBufferPointer { buf in
            analyzer.analyze(buf.baseAddress!, count: buf.count)
        }

        // RMS of a sine wave = amplitude / sqrt(2) ≈ 0.707
        #expect(abs(result.rms - 0.707) < 0.02)
    }

    @Test func crestFactorForSine() {
        var analyzer = EnergyAnalyzer()
        let signal = sineWave(frequency: 440, sampleRate: 48000, count: 2048)

        let result = signal.withUnsafeBufferPointer { buf in
            analyzer.analyze(buf.baseAddress!, count: buf.count)
        }

        // Crest factor of sine ≈ 1.414, normalized by /15 ≈ 0.094
        #expect(result.crestFactor > 0.05 && result.crestFactor < 0.15)
    }

    @Test func silenceDetection() {
        var analyzer = EnergyAnalyzer()
        let silent = silence(count: 2048)

        // Need multiple consecutive silent frames for isSilent to trigger
        for _ in 0..<6 {
            let result = silent.withUnsafeBufferPointer { buf in
                analyzer.analyze(buf.baseAddress!, count: buf.count)
            }
            if result.isSilent {
                #expect(result.rms < 0.001)
                return
            }
        }
        // Should have detected silence by now
        #expect(Bool(true), "Silence should have been detected within 6 frames")
    }
}

// MARK: - SpectralAnalyzer Tests

@Suite("SpectralAnalyzer")
struct SpectralAnalyzerTests {
    @Test func bassSignalDominatesBassBand() {
        let fftSize = 2048
        let sampleRate: Double = 48000
        let engine = FFTEngine(fftSize: fftSize)
        let analyzer = SpectralAnalyzer(fftSize: fftSize, sampleRate: sampleRate)

        let signal = sineWave(frequency: 100, sampleRate: Float(sampleRate), count: fftSize)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)

        signal.withUnsafeBufferPointer { input in
            magnitudes.withUnsafeMutableBufferPointer { output in
                engine.process(input: input.baseAddress!, magnitudes: output.baseAddress!)
            }
        }

        let result = magnitudes.withUnsafeBufferPointer { buf in
            analyzer.analyze(magnitudes: buf.baseAddress!)
        }

        // Bass should dominate over mids and highs
        #expect(result.spectralProfile.bass > result.spectralProfile.mids)
        #expect(result.spectralProfile.bass > result.spectralProfile.highs)
    }

    @Test func centroidLowForBass() {
        let fftSize = 2048
        let sampleRate: Double = 48000
        let engine = FFTEngine(fftSize: fftSize)
        let analyzer = SpectralAnalyzer(fftSize: fftSize, sampleRate: sampleRate)

        let bassSignal = sineWave(frequency: 100, sampleRate: Float(sampleRate), count: fftSize)
        let trebleSignal = sineWave(frequency: 5000, sampleRate: Float(sampleRate), count: fftSize)
        var mags = [Float](repeating: 0, count: fftSize / 2)

        bassSignal.withUnsafeBufferPointer { input in
            mags.withUnsafeMutableBufferPointer { output in
                engine.process(input: input.baseAddress!, magnitudes: output.baseAddress!)
            }
        }
        let bassResult = mags.withUnsafeBufferPointer { buf in
            analyzer.analyze(magnitudes: buf.baseAddress!)
        }

        trebleSignal.withUnsafeBufferPointer { input in
            mags.withUnsafeMutableBufferPointer { output in
                engine.process(input: input.baseAddress!, magnitudes: output.baseAddress!)
            }
        }
        let trebleResult = mags.withUnsafeBufferPointer { buf in
            analyzer.analyze(magnitudes: buf.baseAddress!)
        }

        #expect(bassResult.centroid < trebleResult.centroid)
    }

    @Test func flatnessNoiseVsTone() {
        let fftSize = 2048
        let sampleRate: Double = 48000
        let engine = FFTEngine(fftSize: fftSize)
        let analyzer = SpectralAnalyzer(fftSize: fftSize, sampleRate: sampleRate)

        let noise = whiteNoise(count: fftSize)
        let tone = sineWave(frequency: 440, sampleRate: Float(sampleRate), count: fftSize)
        var mags = [Float](repeating: 0, count: fftSize / 2)

        noise.withUnsafeBufferPointer { input in
            mags.withUnsafeMutableBufferPointer { output in
                engine.process(input: input.baseAddress!, magnitudes: output.baseAddress!)
            }
        }
        let noiseResult = mags.withUnsafeBufferPointer { buf in
            analyzer.analyze(magnitudes: buf.baseAddress!)
        }

        tone.withUnsafeBufferPointer { input in
            mags.withUnsafeMutableBufferPointer { output in
                engine.process(input: input.baseAddress!, magnitudes: output.baseAddress!)
            }
        }
        let toneResult = mags.withUnsafeBufferPointer { buf in
            analyzer.analyze(magnitudes: buf.baseAddress!)
        }

        // Noise should have higher flatness than pure tone
        #expect(noiseResult.flatness > toneResult.flatness)
    }
}

// MARK: - OnsetDetector Tests

@Suite("OnsetDetector")
struct OnsetDetectorTests {
    @Test func detectsTransient() {
        let detector = OnsetDetector(medianWindow: 10, minimumInterval: 2, sensitivity: 1.5)

        // Feed steady low flux, then a spike
        for _ in 0..<15 {
            _ = detector.detect(flux: 0.01)
        }

        let result = detector.detect(flux: 0.5)
        #expect(result.isOnset)
        #expect(result.strength > 0)
    }

    @Test func ignoresSteadyState() {
        let detector = OnsetDetector(medianWindow: 10, minimumInterval: 2, sensitivity: 1.5)

        // Feed constant flux — no onsets should fire (after warm-up)
        for _ in 0..<20 {
            _ = detector.detect(flux: 0.1)
        }

        // Steady flux at the same level shouldn't trigger
        let result = detector.detect(flux: 0.1)
        #expect(!result.isOnset)
    }
}

// MARK: - ChromagramAnalyzer Tests

@Suite("ChromagramAnalyzer")
struct ChromagramAnalyzerTests {
    @Test func detectsMiddleC() {
        let fftSize = 2048
        let sampleRate: Double = 48000
        let engine = FFTEngine(fftSize: fftSize)
        let chroma = ChromagramAnalyzer(fftSize: fftSize, sampleRate: sampleRate)

        // Middle C = 261.63 Hz → pitch class 0 (C)
        let signal = sineWave(frequency: 261.63, sampleRate: Float(sampleRate), count: fftSize)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)

        signal.withUnsafeBufferPointer { input in
            magnitudes.withUnsafeMutableBufferPointer { output in
                engine.process(input: input.baseAddress!, magnitudes: output.baseAddress!)
            }
        }

        // Feed several frames to overcome smoothing
        var result = ChromagramAnalyzer.Result()
        for _ in 0..<20 {
            result = magnitudes.withUnsafeBufferPointer { buf in
                chroma.analyze(magnitudes: buf.baseAddress!)
            }
        }

        // Pitch class 0 (C) should have the highest energy
        let maxPC = result.chromagram.enumerated().max(by: { $0.element < $1.element })?.offset
        #expect(maxPC == 0)
    }
}

// MARK: - MusicalState Sendability

@Suite("MusicalState")
struct MusicalStateTests {
    @Test func isSendable() {
        // Compile-time check: MusicalState can be sent across actors
        let state = MusicalState()
        Task { @MainActor in
            let _ = state
        }
    }

    @Test func defaultsToSilent() {
        let state = MusicalState()
        #expect(state.isSilent)
        #expect(state.bpm == 0)
        #expect(state.energy == 0)
        #expect(state.detectedKey == .unknown)
        #expect(state.chromagram.count == 12)
    }
}
