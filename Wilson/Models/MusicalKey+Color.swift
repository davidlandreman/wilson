import Foundation

extension MusicalKey {
    /// Pitch class index (0 = C, 1 = C#/Db, ... 11 = B). Nil for `.unknown`.
    var pitchClass: Int? {
        switch self {
        case .cMajor, .cMinor: return 0
        case .dbMajor, .cSharpMinor: return 1
        case .dMajor, .dMinor: return 2
        case .ebMajor, .dSharpMinor: return 3
        case .eMajor, .eMinor: return 4
        case .fMajor, .fMinor: return 5
        case .gbMajor, .fSharpMinor: return 6
        case .gMajor, .gMinor: return 7
        case .abMajor, .gSharpMinor: return 8
        case .aMajor, .aMinor: return 9
        case .bbMajor, .aSharpMinor: return 10
        case .bMajor, .bMinor: return 11
        case .unknown: return nil
        }
    }

    var isMajor: Bool {
        switch self {
        case .cMajor, .dbMajor, .dMajor, .ebMajor, .eMajor, .fMajor,
             .gbMajor, .gMajor, .abMajor, .aMajor, .bbMajor, .bMajor:
            return true
        default:
            return false
        }
    }

    var isMinor: Bool {
        switch self {
        case .cMinor, .cSharpMinor, .dMinor, .dSharpMinor, .eMinor, .fMinor,
             .fSharpMinor, .gMinor, .gSharpMinor, .aMinor, .aSharpMinor, .bMinor:
            return true
        default:
            return false
        }
    }

    /// Hue angle (0–360) mapped via circle of fifths → color wheel.
    /// C=0° (red), G=30°, D=60° (yellow), A=90°, E=120° (green), B=150°,
    /// F#=180° (cyan), Db=210°, Ab=240° (blue), Eb=270°, Bb=300° (purple), F=330°.
    var hue: Double? {
        guard let pc = pitchClass else { return nil }
        // Circle of fifths order: C, G, D, A, E, B, F#, Db, Ab, Eb, Bb, F
        // Pitch classes in fifths order: 0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5
        let fifthsOrder: [Int: Double] = [
            0: 0,     // C
            7: 30,    // G
            2: 60,    // D
            9: 90,    // A
            4: 120,   // E
            11: 150,  // B
            6: 180,   // F#/Gb
            1: 210,   // Db/C#
            8: 240,   // Ab/G#
            3: 270,   // Eb/D#
            10: 300,  // Bb/A#
            5: 330,   // F
        ]
        return fifthsOrder[pc]
    }

    /// Whether this key's color temperature leans warm (red/yellow/orange side).
    /// Returns 0–1 where 1 = very warm, 0 = very cool.
    var warmth: Double? {
        guard let h = hue else { return nil }
        // Warm colors: 300–60° (reds, oranges, yellows)
        // Cool colors: 120–240° (greens, cyans, blues)
        // Map to warmth: 0° = 1.0 (warmest), 180° = 0.0 (coolest)
        let normalized = h / 360.0
        // Cosine gives us warm at 0°/360° and cool at 180°
        return (cos(normalized * 2 * .pi) + 1) / 2
    }
}
