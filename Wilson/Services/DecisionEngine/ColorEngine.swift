import Foundation

/// Resolves a raw ColorPalette into a ResolvedPalette with mood-influenced
/// warm/cool bias and musical key color relationships.
struct ColorEngine: Sendable {
    /// Default palette when none is active.
    private static let defaultPalette = ResolvedPalette(
        colors: [
            LightColor(red: 0.2, green: 0.4, blue: 1.0, white: 0),   // Blue
            LightColor(red: 0.8, green: 0.2, blue: 0.8, white: 0),   // Purple
            LightColor(red: 1.0, green: 0.3, blue: 0.1, white: 0),   // Orange-red
            LightColor(red: 0.1, green: 0.9, blue: 0.5, white: 0),   // Teal
        ],
        warmBias: 0.5
    )

    func resolve(
        palette: ColorPalette?,
        mood: MoodState,
        musicalState: MusicalState
    ) -> ResolvedPalette {
        guard let palette, !palette.colors.isEmpty else {
            return Self.defaultPalette
        }

        // Compute warm/cool bias from mood + key
        var warmBias = mood.brightness // Spectral centroid → base warmth

        // Musical key influence: warm keys bias warmer, cool keys bias cooler
        if musicalState.keyConfidence > 0.4,
           let keyWarmth = musicalState.detectedKey.warmth {
            warmBias = warmBias * 0.6 + keyWarmth * 0.4
        }

        // Major keys feel slightly warmer, minor slightly cooler
        if musicalState.detectedKey.isMajor {
            warmBias = min(1, warmBias + 0.05)
        } else if musicalState.detectedKey.isMinor {
            warmBias = max(0, warmBias - 0.05)
        }

        return ResolvedPalette(
            colors: palette.colors,
            warmBias: warmBias
        )
    }
}
