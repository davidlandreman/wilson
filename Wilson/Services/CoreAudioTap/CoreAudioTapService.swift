import Foundation
import AVFoundation
import CoreAudio
import AppKit
import Accelerate
import os

// MARK: - Errors

enum CoreAudioTapError: Error, LocalizedError {
    case processNotRunning(String)
    case processNotPlayingAudio(String)
    case tapCreationFailed(OSStatus)
    case aggregateDeviceCreationFailed(OSStatus)
    case formatQueryFailed(OSStatus)
    case ioProcCreationFailed(OSStatus)
    case startFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .processNotRunning(let id):
            "\(id) is not running — launch it and try again"
        case .processNotPlayingAudio(let name):
            "\(name) has no active audio — start playing music and try again"
        case .tapCreationFailed(let s):
            "Failed to create audio tap (OSStatus \(s))"
        case .aggregateDeviceCreationFailed(let s):
            "Failed to create aggregate device (OSStatus \(s))"
        case .formatQueryFailed(let s):
            "Failed to query audio format (OSStatus \(s))"
        case .ioProcCreationFailed(let s):
            "Failed to create IO proc (OSStatus \(s))"
        case .startFailed(let s):
            "Failed to start audio capture (OSStatus \(s))"
        }
    }
}

// MARK: - CoreAudioTapService

/// Captures audio output from a specific app (default: Music.app) via Core Audio process taps.
/// Produces the same (AVAudioPCMBuffer, AVAudioTime) callback as AudioCaptureService.
@Observable
final class CoreAudioTapService {
    private(set) var isCapturing = false
    private(set) var audioLevel: Float = 0
    private(set) var targetProcessName: String?

    /// Raw audio buffer callback for downstream analysis.
    /// Called on the audio IO thread — not the main thread.
    @ObservationIgnored
    var onAudioBuffer: ((_ buffer: AVAudioPCMBuffer, _ time: AVAudioTime) -> Void)?

    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var activityToken: NSObjectProtocol?
    private static let logger = Logger(subsystem: "com.landreman.Wilson", category: "CoreAudioTap")

    @MainActor func startCapture(bundleID: String = "com.apple.Music") async throws {
        guard !isCapturing else { return }

        // 1. Find the target process
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            throw CoreAudioTapError.processNotRunning(bundleID)
        }
        let pid = app.processIdentifier
        let processName = app.localizedName ?? bundleID
        targetProcessName = processName

        // 2. Translate PID → Core Audio process object ID
        guard let processObjectID = Self.audioObjectID(for: pid) else {
            throw CoreAudioTapError.processNotPlayingAudio(processName)
        }

        // 3. Create a stereo mixdown tap on the target process
        let tapDesc = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        tapDesc.name = "Wilson Audio Tap"

        var newTapID: AudioObjectID = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(tapDesc, &newTapID)
        guard tapStatus == noErr else {
            throw CoreAudioTapError.tapCreationFailed(tapStatus)
        }
        self.tapID = newTapID
        Self.logger.info("Created process tap (ID \(newTapID)) for \(processName, privacy: .public)")

        // 4. Create a private aggregate device that reads from the tap
        let tapUID = tapDesc.uuid.uuidString
        let aggregateConfig: NSDictionary = [
            kAudioAggregateDeviceNameKey: "Wilson Tap",
            kAudioAggregateDeviceUIDKey: "com.landreman.Wilson.tap.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUID]
            ],
            kAudioAggregateDeviceIsStackedKey: 0,
        ]

        var newAggID: AudioObjectID = kAudioObjectUnknown
        let aggStatus = AudioHardwareCreateAggregateDevice(aggregateConfig, &newAggID)
        guard aggStatus == noErr else {
            destroyTap()
            throw CoreAudioTapError.aggregateDeviceCreationFailed(aggStatus)
        }
        self.aggregateDeviceID = newAggID
        Self.logger.info("Created aggregate device (ID \(newAggID))")

        // 5. Query the input stream format from the aggregate device
        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let formatStatus = AudioObjectGetPropertyData(
            newAggID, &formatAddress, 0, nil, &formatSize, &asbd
        )
        guard formatStatus == noErr else {
            destroyAggregateDevice()
            destroyTap()
            throw CoreAudioTapError.formatQueryFailed(formatStatus)
        }

        guard let avFormat = AVAudioFormat(streamDescription: &asbd) else {
            destroyAggregateDevice()
            destroyTap()
            throw CoreAudioTapError.formatQueryFailed(0)
        }

        let sampleRate = asbd.mSampleRate
        let bytesPerFrame = asbd.mBytesPerFrame
        Self.logger.info("Tap format: \(asbd.mSampleRate)Hz, \(asbd.mChannelsPerFrame)ch, \(asbd.mBitsPerChannel)bit, bpf=\(bytesPerFrame)")

        // 6. Set up IO proc — must be built outside @MainActor isolation
        //    so the callback closure doesn't inherit actor context.
        let bufferCallback = onAudioBuffer
        weak let weakSelf = self

        let procID = try Self.createIOProc(
            aggregateDeviceID: newAggID,
            avFormat: avFormat,
            bytesPerFrame: bytesPerFrame,
            sampleRate: sampleRate,
            bufferCallback: bufferCallback,
            levelCallback: { rms in
                Task { @MainActor in
                    guard let self = weakSelf else { return }
                    self.audioLevel = 0.3 * rms + 0.7 * self.audioLevel
                }
            }
        )
        self.ioProcID = procID

        // 7. Start IO
        let startStatus = AudioDeviceStart(newAggID, procID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(newAggID, procID)
            self.ioProcID = nil
            destroyAggregateDevice()
            destroyTap()
            throw CoreAudioTapError.startFailed(startStatus)
        }

        isCapturing = true
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Real-time audio capture via Core Audio Tap"
        )
        Self.logger.info("Core Audio Tap started — capturing \(processName, privacy: .public)")
    }

    @MainActor func stopCapture() async {
        guard isCapturing else { return }

        if let ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }
        self.ioProcID = nil

        destroyAggregateDevice()
        destroyTap()

        activityToken = nil
        isCapturing = false
        audioLevel = 0
        targetProcessName = nil
        Self.logger.info("Core Audio Tap stopped")
    }

    // MARK: - IO Proc Setup

    /// Creates the IO proc and starts it on a dedicated dispatch queue.
    /// Static (nonisolated) so the callback closure does not inherit @MainActor isolation.
    private static func createIOProc(
        aggregateDeviceID: AudioObjectID,
        avFormat: AVAudioFormat,
        bytesPerFrame: UInt32,
        sampleRate: Double,
        bufferCallback: ((_ buffer: AVAudioPCMBuffer, _ time: AVAudioTime) -> Void)?,
        levelCallback: @escaping (Float) -> Void
    ) throws -> AudioDeviceIOProcID {
        let audioQueue = DispatchQueue(
            label: "com.landreman.Wilson.coreaudiotap",
            qos: .userInteractive
        )

        // Diagnostics: log the first few callbacks to verify data flow
        let callCount = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        callCount.initialize(to: 0)

        var ioProcID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(
            &ioProcID, aggregateDeviceID, audioQueue
        ) { _, inInputData, inInputTime, _, _ in
            let count = callCount.pointee
            callCount.pointee = count + 1

            let numBuffers = Int(inInputData.pointee.mNumberBuffers)

            if count < 5 {
                let firstBuf = inInputData.pointee.mBuffers
                logger.info("IO callback #\(count): numBuffers=\(numBuffers), buf0.size=\(firstBuf.mDataByteSize), buf0.channels=\(firstBuf.mNumberChannels), bytesPerFrame=\(bytesPerFrame)")
            }

            guard bytesPerFrame > 0 else { return }

            // Determine frame count from the first buffer
            let firstBuffer = inInputData.pointee.mBuffers
            guard firstBuffer.mDataByteSize > 0 else { return }
            let frameCount = AVAudioFrameCount(firstBuffer.mDataByteSize / bytesPerFrame)
            guard frameCount > 0 else { return }

            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: avFormat, frameCapacity: frameCount) else { return }
            pcmBuffer.frameLength = frameCount

            // Copy audio data — UnsafeMutableAudioBufferListPointer safely
            // traverses the variable-length AudioBufferList
            let srcList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            let dstList = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
            for i in 0..<min(srcList.count, dstList.count) {
                guard let srcData = srcList[i].mData,
                      let dstData = dstList[i].mData else { continue }
                let size = min(srcList[i].mDataByteSize, dstList[i].mDataByteSize)
                memcpy(dstData, srcData, Int(size))
            }

            // RMS level from first channel
            if let channelData = pcmBuffer.floatChannelData, pcmBuffer.frameLength > 0 {
                var rms: Float = 0
                vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(pcmBuffer.frameLength))
                levelCallback(rms)
            }

            let sampleTime = AVAudioFramePosition(inInputTime.pointee.mSampleTime)
            let time = AVAudioTime(sampleTime: sampleTime, atRate: sampleRate)
            bufferCallback?(pcmBuffer, time)
        }

        guard status == noErr, let procID = ioProcID else {
            throw CoreAudioTapError.ioProcCreationFailed(status)
        }
        return procID
    }

    // MARK: - PID Translation

    /// Translates a Unix PID into a Core Audio process AudioObjectID.
    /// Returns nil if the process has no active audio.
    private static func audioObjectID(for pid: pid_t) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize
        )
        guard status == noErr, dataSize > 0 else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var processObjectIDs = [AudioObjectID](repeating: kAudioObjectUnknown, count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize, &processObjectIDs
        )
        guard status == noErr else { return nil }

        for objectID in processObjectIDs {
            var pidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var processPID: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            let pidStatus = AudioObjectGetPropertyData(
                objectID, &pidAddress, 0, nil, &pidSize, &processPID
            )
            if pidStatus == noErr && processPID == pid {
                logger.info("Resolved PID \(pid) → AudioObjectID \(objectID)")
                return objectID
            }
        }

        return nil
    }

    // MARK: - Cleanup

    private func destroyAggregateDevice() {
        guard aggregateDeviceID != kAudioObjectUnknown else { return }
        AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        aggregateDeviceID = kAudioObjectUnknown
    }

    private func destroyTap() {
        guard tapID != kAudioObjectUnknown else { return }
        AudioHardwareDestroyProcessTap(tapID)
        tapID = kAudioObjectUnknown
    }
}
