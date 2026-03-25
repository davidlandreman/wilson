import Foundation
import AVFoundation
import os

/// Generates a drum-pattern test signal at a configurable BPM.
/// Feeds audio into the analysis pipeline and plays through speakers.
@Observable
final class TestAudioService {
    private(set) var isPlaying = false

    /// BPM for the generated pattern (60–200). Updates take effect immediately.
    var bpm: Double = 120.0 {
        didSet { _renderBPM.value = bpm }
    }

    /// Audio buffer callback — same signature as AudioCaptureService.
    /// Wired by AppState to feed the analysis pipeline.
    @ObservationIgnored var onAudioBuffer: ((_ buffer: AVAudioPCMBuffer, _ time: AVAudioTime) -> Void)?

    @ObservationIgnored private let _renderBPM = SharedDouble(120.0)
    private var engine: AVAudioEngine?
    private static let sampleRate: Double = 48000
    private static let logger = Logger(subsystem: "com.landreman.Wilson", category: "TestAudio")

    @MainActor func start() throws {
        guard !isPlaying else { return }

        let bufferCallback = onAudioBuffer
        let engine = Self.buildEngine(sampleRate: Self.sampleRate, bpm: _renderBPM, bufferCallback: bufferCallback)
        try engine.start()

        self.engine = engine
        isPlaying = true
        Self.logger.info("Test audio started at \(self.bpm) BPM")
    }

    /// Builds the entire AVAudioEngine graph outside @MainActor isolation
    /// so that neither the render block nor the tap closure inherit
    /// MainActor isolation — both must run on the real-time audio thread.
    private static func buildEngine(
        sampleRate: Double,
        bpm: SharedDouble,
        bufferCallback: ((_ buffer: AVAudioPCMBuffer, _ time: AVAudioTime) -> Void)?
    ) -> AVAudioEngine {
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let renderState = RenderState(sampleRate: sampleRate, bpm: bpm)

        let sourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, outputData in
            renderState.render(frameCount: frameCount, outputData: outputData)
            return noErr
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)

        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
            bufferCallback?(buffer, time)
        }

        return engine
    }

    @MainActor func stop() {
        guard let engine else { return }
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        isPlaying = false
        Self.logger.info("Test audio stopped")
    }
}

// MARK: - Thread-Safe BPM Sharing

/// Lock-protected Double shared between the main thread and the audio render thread.
private final class SharedDouble: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Double

    init(_ value: Double) {
        _value = value
    }

    var value: Double {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

// MARK: - Audio Render State

/// Holds synthesis state for the real-time audio render callback.
/// Only accessed from the audio render thread (sequential, never concurrent).
/// SharedDouble for BPM is the sole shared state with the main thread.
private final class RenderState: @unchecked Sendable {
    let sampleRate: Double
    let bpm: SharedDouble

    var samplePosition: Int64 = 0
    var kickPhase: Double = 0
    var snarePhase: Double = 0

    init(sampleRate: Double, bpm: SharedDouble) {
        self.sampleRate = sampleRate
        self.bpm = bpm
    }

    func render(frameCount: UInt32, outputData: UnsafeMutablePointer<AudioBufferList>) {
        let ablPointer = UnsafeMutableAudioBufferListPointer(outputData)
        let currentBPM = bpm.value
        let beatInterval = sampleRate * 60.0 / currentBPM

        for frame in 0..<Int(frameCount) {
            let pos = Double(samplePosition)

            // Position within current beat
            let posInBeat = pos.truncatingRemainder(dividingBy: beatInterval)
            let timeSinceBeat = posInBeat / sampleRate

            // Which beat in the 4-beat bar (0–3)
            let barInterval = beatInterval * 4.0
            let posInBar = pos.truncatingRemainder(dividingBy: barInterval)
            let beatInBar = Int(posInBar / beatInterval)

            // Position within 8th note
            let eighthInterval = beatInterval / 2.0
            let posIn8th = pos.truncatingRemainder(dividingBy: eighthInterval)
            let timeSince8th = posIn8th / sampleRate

            var sample: Float = 0

            // Kick drum on every beat (four-on-the-floor)
            if timeSinceBeat < 0.15 {
                // Pitch sweep from ~155Hz down to ~55Hz
                let freq = 55.0 + 100.0 * exp(-timeSinceBeat * 30.0)
                kickPhase += freq / sampleRate
                let env = Float(exp(-timeSinceBeat * 12.0))
                sample += sin(Float(kickPhase * 2.0 * .pi)) * env * 0.7
            }

            // Snare on beats 1 and 3 (backbeat)
            if (beatInBar == 1 || beatInBar == 3) && timeSinceBeat < 0.08 {
                snarePhase += 180.0 / sampleRate
                let env = Float(exp(-timeSinceBeat * 25.0))
                let tone = sin(Float(snarePhase * 2.0 * .pi))
                let noise = Float.random(in: -1...1)
                sample += (tone * 0.3 + noise * 0.5) * env * 0.4
            }

            // Hi-hat on every 8th note
            if timeSince8th < 0.025 {
                let env = Float(exp(-timeSince8th * 100.0))
                let noise = Float.random(in: -1...1)
                sample += noise * env * 0.15
            }

            // Write to all channels (stereo — same signal both sides)
            for bufferIndex in 0..<ablPointer.count {
                let buf = ablPointer[bufferIndex]
                let data = buf.mData!.assumingMemoryBound(to: Float.self)
                data[frame] = sample
            }

            samplePosition += 1
        }
    }
}
