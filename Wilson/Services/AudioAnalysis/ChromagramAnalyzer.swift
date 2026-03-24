import Accelerate
import Foundation

/// Maps FFT magnitude bins to 12 pitch classes and detects musical key
/// using the Krumhansl-Schmuckler algorithm.
final class ChromagramAnalyzer: @unchecked Sendable {
    struct Result {
        var chromagram: [Double] = Array(repeating: 0, count: 12)
        var detectedKey: MusicalKey = .unknown
        var keyConfidence: Double = 0
    }

    private let binCount: Int
    private let sampleRate: Double
    private let fftSize: Int

    /// Weight matrix: pitchClassWeights[pc] = [(binIndex, weight)] for each pitch class.
    private let pitchClassBins: [[Int]]

    /// Smoothed chromagram (EMA).
    private var smoothedChroma: [Double] = Array(repeating: 0, count: 12)
    private let smoothingAlpha: Double = 0.15

    /// Key stability tracking.
    private var lastDetectedKey: MusicalKey = .unknown
    private var keyStableFrames: Int = 0
    private let keyStabilityRequired: Int  // ~2 seconds

    /// Krumhansl-Kessler key profiles (major and minor).
    private static let majorProfile: [Double] = [
        6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88
    ]
    private static let minorProfile: [Double] = [
        6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17
    ]

    /// All 24 key profiles (12 rotations × 2 modes), pre-computed.
    private let keyProfiles: [(key: MusicalKey, profile: [Double])]

    /// Pitch class names for display.
    static let pitchClassNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    init(fftSize: Int = 2048, sampleRate: Double = 48000, analysisRate: Double = 47) {
        self.fftSize = fftSize
        self.binCount = fftSize / 2
        self.sampleRate = sampleRate
        self.keyStabilityRequired = Int(analysisRate * 2) // ~2 seconds

        // Map each FFT bin to its nearest pitch class (for bins in range ~65Hz to ~2100Hz)
        let minBin = max(1, Int(round(65.0 * Double(fftSize) / sampleRate)))   // C2
        let maxBin = min(binCount - 1, Int(round(2100.0 * Double(fftSize) / sampleRate)))  // C7

        var bins: [[Int]] = Array(repeating: [], count: 12)
        for bin in minBin...maxBin {
            let freq = Double(bin) * sampleRate / Double(fftSize)
            guard freq > 0 else { continue }
            let midiNote = 69.0 + 12.0 * log2(freq / 440.0)
            let pitchClass = ((Int(round(midiNote)) % 12) + 12) % 12
            bins[pitchClass].append(bin)
        }
        self.pitchClassBins = bins

        // Pre-compute all 24 key profiles
        var profiles: [(MusicalKey, [Double])] = []

        let majorKeys: [MusicalKey] = [
            .cMajor, .dbMajor, .dMajor, .ebMajor, .eMajor, .fMajor,
            .gbMajor, .gMajor, .abMajor, .aMajor, .bbMajor, .bMajor
        ]
        let minorKeys: [MusicalKey] = [
            .cMinor, .cSharpMinor, .dMinor, .dSharpMinor, .eMinor, .fMinor,
            .fSharpMinor, .gMinor, .gSharpMinor, .aMinor, .aSharpMinor, .bMinor
        ]

        for (i, key) in majorKeys.enumerated() {
            let rotated = Self.rotateProfile(Self.majorProfile, by: i)
            profiles.append((key, rotated))
        }
        for (i, key) in minorKeys.enumerated() {
            let rotated = Self.rotateProfile(Self.minorProfile, by: i)
            profiles.append((key, rotated))
        }

        self.keyProfiles = profiles
    }

    /// Analyze the magnitude spectrum and return chromagram + key detection.
    func analyze(magnitudes: UnsafePointer<Float>) -> Result {
        var result = Result()

        // Compute raw chromagram: sum magnitudes for each pitch class
        var rawChroma = [Double](repeating: 0, count: 12)
        for pc in 0..<12 {
            for bin in pitchClassBins[pc] {
                rawChroma[pc] += Double(magnitudes[bin])
            }
        }

        // Normalize
        let maxChroma = rawChroma.max() ?? 0
        if maxChroma > 0 {
            for i in 0..<12 {
                rawChroma[i] /= maxChroma
            }
        }

        // Temporal smoothing (EMA)
        for i in 0..<12 {
            smoothedChroma[i] = smoothingAlpha * rawChroma[i] + (1.0 - smoothingAlpha) * smoothedChroma[i]
        }
        result.chromagram = smoothedChroma

        // Key detection via Krumhansl-Schmuckler correlation
        var bestKey: MusicalKey = .unknown
        var bestCorrelation: Double = -1

        for (key, profile) in keyProfiles {
            let r = pearsonCorrelation(smoothedChroma, profile)
            if r > bestCorrelation {
                bestCorrelation = r
                bestKey = key
            }
        }

        // Key stability: require consistent detection before reporting change
        if bestKey == lastDetectedKey {
            keyStableFrames += 1
        } else {
            lastDetectedKey = bestKey
            keyStableFrames = 1
        }

        if keyStableFrames >= keyStabilityRequired {
            result.detectedKey = bestKey
            result.keyConfidence = max(0, min(bestCorrelation, 1.0))
        } else if keyStableFrames > keyStabilityRequired / 4 {
            // Partial confidence during transition
            result.detectedKey = bestKey
            result.keyConfidence = max(0, min(bestCorrelation * 0.5, 1.0))
        }

        return result
    }

    // MARK: - Helpers

    /// Rotate a profile array by `semitones` positions.
    private static func rotateProfile(_ profile: [Double], by semitones: Int) -> [Double] {
        let n = profile.count
        return (0..<n).map { profile[((($0 - semitones) % n) + n) % n] }
    }

    /// Pearson correlation between two 12-element vectors.
    private func pearsonCorrelation(_ a: [Double], _ b: [Double]) -> Double {
        let n = Double(a.count)
        var sumA: Double = 0, sumB: Double = 0
        var sumAB: Double = 0, sumA2: Double = 0, sumB2: Double = 0

        for i in 0..<a.count {
            sumA += a[i]
            sumB += b[i]
            sumAB += a[i] * b[i]
            sumA2 += a[i] * a[i]
            sumB2 += b[i] * b[i]
        }

        let numerator = n * sumAB - sumA * sumB
        let denominator = sqrt((n * sumA2 - sumA * sumA) * (n * sumB2 - sumB * sumB))
        return denominator > 0 ? numerator / denominator : 0
    }
}
