import Foundation

/// Maps frequency band energy to RGB, constrained to the active palette's color space.
/// Bass emphasizes warm palette colors, highs emphasize cool palette colors,
/// mids blend between them.
struct SpectralColorBehavior: Behavior {
    static let id = "spectralColor"

    let controlledAttributes: Set<FixtureAttribute> = [.red, .green, .blue, .white]

    func evaluate(
        fixtures: [StageFixture],
        context: BehaviorContext
    ) -> [UUID: [FixtureAttribute: Double]] {
        let sp = context.musicalState.spectralProfile
        let palette = context.palette
        let intensity = context.parameters.intensity

        // Blend between palette colors based on spectral balance
        // Low frequencies → primary (warm), high frequencies → secondary (cool)
        let lowEnergy = sp.subBass * 0.4 + sp.bass * 0.6
        let midEnergy = sp.mids
        let highEnergy = sp.highs * 0.6 + sp.presence * 0.4

        // Normalize the blend weights
        let total = max(0.001, lowEnergy + midEnergy + highEnergy)
        let lowWeight = lowEnergy / total
        let midWeight = midEnergy / total
        let highWeight = highEnergy / total

        let lowColor = palette.primary()
        let midColor = palette.secondary()
        let highColor = palette.accent()

        // Weighted blend of palette colors
        let blended = LightColor(
            red: (lowColor.red * lowWeight + midColor.red * midWeight + highColor.red * highWeight),
            green: (lowColor.green * lowWeight + midColor.green * midWeight + highColor.green * highWeight),
            blue: (lowColor.blue * lowWeight + midColor.blue * midWeight + highColor.blue * highWeight),
            white: (lowColor.white * lowWeight + midColor.white * midWeight + highColor.white * highWeight)
        )

        // Scale by overall energy for reactivity
        let energyScale = context.musicalState.energy * 0.5 + 0.5
        let scaled = blended.scaled(by: energyScale * intensity)

        var result: [UUID: [FixtureAttribute: Double]] = [:]
        for fixture in fixtures {
            guard fixture.attributes.contains(.red) || fixture.attributes.contains(.colorWheel) else { continue }
            result[fixture.id] = [
                .red: scaled.red,
                .green: scaled.green,
                .blue: scaled.blue,
                .white: scaled.white,
            ]
        }
        return result
    }
}
