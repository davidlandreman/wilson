import Foundation

/// Records decision engine telemetry at 1-second intervals for offline analysis.
/// Produces a JSON file with timestamped snapshots of the full pipeline state.
@MainActor @Observable
final class TelemetryRecorder {
    private(set) var isRecording = false
    private(set) var samples: [Sample] = []
    private(set) var elapsed: TimeInterval = 0

    private var startTime: Date?
    private var lastSampleTime: Date?
    private let sampleInterval: TimeInterval = 1.0

    /// Call every frame from the engine update loop. Samples at ~1s intervals.
    func tick(musicalState: MusicalState, mood: MoodState, scenario: Choreographer.Scenario, slots: [String]) {
        guard isRecording, let start = startTime else { return }

        let now = Date()
        elapsed = now.timeIntervalSince(start)

        if let last = lastSampleTime, now.timeIntervalSince(last) < sampleInterval {
            return
        }
        lastSampleTime = now

        let sample = Sample(
            t: round(elapsed * 10) / 10,
            energy: musicalState.energy,
            rawEnergy: musicalState.rawEnergy,
            normCeiling: musicalState.normalizationCeiling,
            peakEnergy: mood.peakEnergy,
            intensity: mood.intensity,
            excitement: mood.excitement,
            brightness: mood.brightness,
            chaos: mood.chaos,
            valence: mood.valence,
            trajectory: mood.energyTrajectory.label,
            scenario: scenario.label,
            bpm: musicalState.bpm,
            isBeat: musicalState.isBeat,
            isSilent: musicalState.isSilent,
            key: musicalState.detectedKey.displayName,
            crestFactor: musicalState.crestFactor,
            subBass: musicalState.spectralProfile.subBass,
            bass: musicalState.spectralProfile.bass,
            mids: musicalState.spectralProfile.mids,
            highs: musicalState.spectralProfile.highs,
            presence: musicalState.spectralProfile.presence,
            behaviors: slots
        )
        samples.append(sample)
    }

    func start() {
        samples = []
        startTime = Date()
        lastSampleTime = nil
        elapsed = 0
        isRecording = true
    }

    func stop() {
        isRecording = false
    }

    /// Encode the recording as pretty-printed JSON data.
    func exportJSON() -> Data? {
        let recording = Recording(
            recordedAt: startTime?.ISO8601Format() ?? "",
            durationSeconds: round(elapsed * 10) / 10,
            sampleCount: samples.count,
            sampleIntervalSeconds: sampleInterval,
            samples: samples
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(recording)
    }

    // MARK: - Data types

    struct Recording: Codable {
        let recordedAt: String
        let durationSeconds: Double
        let sampleCount: Int
        let sampleIntervalSeconds: Double
        let samples: [Sample]
    }

    struct Sample: Codable {
        let t: Double             // seconds since recording start
        let energy: Double        // normalized energy (0-1)
        let rawEnergy: Double     // pre-normalization RMS
        let normCeiling: Double   // adaptive normalization ceiling
        let peakEnergy: Double    // peak-hold envelope
        let intensity: Double     // smoothed (asymmetric EMA)
        let excitement: Double
        let brightness: Double
        let chaos: Double
        let valence: Double
        let trajectory: String
        let scenario: String
        let bpm: Double
        let isBeat: Bool
        let isSilent: Bool
        let key: String
        let crestFactor: Double
        let subBass: Double
        let bass: Double
        let mids: Double
        let highs: Double
        let presence: Double
        let behaviors: [String]
    }
}

// MARK: - Label helpers

extension EnergyTrajectory {
    var label: String {
        switch self {
        case .building: "building"
        case .sustaining: "sustaining"
        case .declining: "declining"
        case .stable: "stable"
        }
    }
}

extension Choreographer.Scenario {
    var label: String {
        switch self {
        case .lowEnergy: "low"
        case .mediumEnergy: "medium"
        case .highEnergy: "high"
        case .building: "building"
        case .peakDrop: "peak"
        case .declining: "declining"
        }
    }
}
