import Foundation
@preconcurrency import ScreenCaptureKit
import AVFoundation
import CoreMedia
import Accelerate
import os

// MARK: - Errors

enum AudioCaptureError: Error, LocalizedError {
    case noDisplayFound

    var errorDescription: String? {
        switch self {
        case .noDisplayFound:
            "No display available for audio capture"
        }
    }
}

// MARK: - AudioCaptureService

/// Captures system audio output via ScreenCaptureKit.
@Observable
final class AudioCaptureService {
    private(set) var isCapturing = false
    private(set) var audioLevel: Float = 0

    /// Raw audio buffer callback for downstream analysis.
    /// Called on a dedicated high-priority audio queue — not the main thread.
    var onAudioBuffer: ((_ buffer: AVAudioPCMBuffer, _ time: AVAudioTime) -> Void)?

    private var stream: SCStream?
    private var streamOutput: AudioStreamOutput?
    private var activityToken: NSObjectProtocol?
    private static let logger = Logger(subsystem: "com.landreman.Wilson", category: "AudioCapture")

    @MainActor func startCapture() async throws {
        guard !isCapturing else { return }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        )

        guard let display = content.displays.first else {
            throw AudioCaptureError.noDisplayFound
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        // Minimize video overhead — we only need audio
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false

        // Capture the callback at start time so the handler doesn't reference self
        let bufferCallback = onAudioBuffer

        let output = AudioStreamOutput(
            onBuffer: { buffer, time in
                bufferCallback?(buffer, time)
            },
            onLevel: { [weak self] rms in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.audioLevel = 0.3 * rms + 0.7 * self.audioLevel
                }
            },
            onError: { [weak self] error in
                Self.logger.error("Stream stopped with error: \(error.localizedDescription)")
                Task { @MainActor [weak self] in
                    self?.isCapturing = false
                    self?.audioLevel = 0
                }
            }
        )

        let audioQueue = DispatchQueue(
            label: "com.landreman.Wilson.audiocapture",
            qos: .userInteractive
        )

        let captureStream = SCStream(filter: filter, configuration: config, delegate: output)
        try captureStream.addStreamOutput(output, type: .audio, sampleHandlerQueue: audioQueue)

        try await captureStream.startCapture()

        self.stream = captureStream
        self.streamOutput = output
        isCapturing = true

        // Prevent App Nap from suspending audio capture when window loses focus
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Real-time audio capture and analysis"
        )

        Self.logger.info("Audio capture started (48kHz stereo)")
    }

    @MainActor func stopCapture() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
        self.streamOutput = nil
        activityToken = nil
        isCapturing = false
        audioLevel = 0

        Self.logger.info("Audio capture stopped")
    }
}

// MARK: - Stream Output Handler

/// Receives raw CMSampleBuffers from ScreenCaptureKit, converts to AVAudioPCMBuffer,
/// calculates RMS level, and forwards via callbacks.
private final class AudioStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let onBuffer: (AVAudioPCMBuffer, AVAudioTime) -> Void
    let onLevel: (Float) -> Void
    let onError: (Error) -> Void

    init(
        onBuffer: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void,
        onLevel: @escaping (Float) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.onBuffer = onBuffer
        self.onLevel = onLevel
        self.onError = onError
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio else { return }
        guard sampleBuffer.isValid, sampleBuffer.numSamples > 0 else { return }

        guard let pcmBuffer = convertToPCMBuffer(sampleBuffer) else { return }

        // RMS level from first channel using vDSP
        var rms: Float = 0
        if let channelData = pcmBuffer.floatChannelData, pcmBuffer.frameLength > 0 {
            vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(pcmBuffer.frameLength))
        }
        onLevel(rms)

        // Build AVAudioTime from presentation timestamp
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let sampleRate = pcmBuffer.format.sampleRate
        let sampleTime = AVAudioFramePosition(pts.seconds * sampleRate)
        let time = AVAudioTime(sampleTime: sampleTime, atRate: sampleRate)

        onBuffer(pcmBuffer, time)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError(error)
    }

    // MARK: - CMSampleBuffer → AVAudioPCMBuffer

    private func convertToPCMBuffer(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              let format = AVAudioFormat(streamDescription: asbd) else {
            return nil
        }

        let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        pcmBuffer.frameLength = frameCount

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: pcmBuffer.mutableAudioBufferList
        )

        guard status == noErr else { return nil }
        return pcmBuffer
    }
}
