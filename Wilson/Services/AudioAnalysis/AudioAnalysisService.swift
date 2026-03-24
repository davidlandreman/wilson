import Foundation
import AVFoundation
import os

/// Real-time audio analysis service. Bridges the DSP pipeline (audio queue)
/// to Observable state consumed by SwiftUI views.
@Observable
final class AudioAnalysisService {
    /// The current musical state — updated at ~47Hz on the main actor.
    fileprivate(set) var musicalState = MusicalState()

    // MARK: - DSP Configuration

    /// FFT size — 2048 samples at 48kHz gives ~42ms windows with ~23Hz resolution.
    static let fftSize = 2048

    /// Hop size — 1024 samples (~21ms), 50% overlap, ~47 analyses/sec.
    static let hopSize = 1024

    // MARK: - Internal State

    @ObservationIgnored private var pipeline: DSPPipeline?
    private static let logger = Logger(subsystem: "com.landreman.Wilson", category: "AudioAnalysis")

    /// Wire this service to the audio capture callback.
    /// Call from AppState before starting capture.
    func makeAudioBufferHandler() -> (AVAudioPCMBuffer, AVAudioTime) -> Void {
        let dsp = DSPPipeline(
            fftSize: Self.fftSize,
            hopSize: Self.hopSize,
            sampleRate: 48000
        )
        self.pipeline = dsp

        // Sendable bridge: holds a weak ref to self, applies state on main actor.
        // @unchecked Sendable is safe because `service` is only written once (init)
        // and only read from @MainActor context (apply).
        let updater = StateUpdater(service: self)

        return { [dsp, updater] buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }

            let samples = UnsafeBufferPointer(start: channelData[0], count: frameCount)

            if let state = dsp.processBuffer(samples) {
                Task { @MainActor in
                    updater.apply(state)
                }
            }
        }
    }

    // MARK: - Layer 2: ML Structure Analysis (Phase 3)

    /// Runs on longer windows (2–8s) for segment classification.
    func analyzeStructure() {
        // TODO: Phase 3 — Core ML model inference
    }
}

// MARK: - Sendable Bridge

/// Bridges state updates from the audio queue to the main-actor-isolated service.
private final class StateUpdater: @unchecked Sendable {
    weak var service: AudioAnalysisService?

    init(service: AudioAnalysisService) {
        self.service = service
    }

    @MainActor func apply(_ state: MusicalState) {
        service?.musicalState = state
    }
}
