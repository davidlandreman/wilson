import Foundation

/// Slowly rotates through palette colors, synced to musical phrasing.
/// Variant 0: all fixtures in unison. Variant 1: rainbow spread (phase offset per fixture).
struct ColorWashBehavior: Behavior {
    static let id = "colorWash"

    let controlledAttributes: Set<FixtureAttribute> = [.red, .green, .blue, .white]

    func evaluate(
        fixtures: [StageFixture],
        context: BehaviorContext
    ) -> [UUID: [FixtureAttribute: Double]] {
        let palette = context.palette
        let colorCount = max(1, palette.colors.count)
        let speed = context.parameters.speed
        let isRainbow = context.parameters.variant == 1

        // Base phase: one full palette cycle per 4 bars (16 beats), continuous time
        let beatsPerSecond = max(1, context.beat.bpm) / 60.0
        let cyclesPerSecond = beatsPerSecond / 16.0 * speed
        let basePhase = context.time * cyclesPerSecond + context.parameters.offset

        var result: [UUID: [FixtureAttribute: Double]] = [:]

        for (index, fixture) in fixtures.enumerated() {
            // Write RGB intent for all fixtures — the FixtureTranslator maps
            // to color wheel or other output as needed.
            guard fixture.attributes.contains(.red) || fixture.attributes.contains(.colorWheel) else { continue }

            // Per-fixture phase offset for rainbow spread
            let fixtureOffset: Double
            if isRainbow && fixtures.count > 1 {
                fixtureOffset = Double(index) / Double(fixtures.count)
            } else {
                fixtureOffset = 0
            }

            let phase = (basePhase + fixtureOffset).truncatingRemainder(dividingBy: 1.0)
            let scaledPhase = phase * Double(colorCount)
            let fromIndex = Int(scaledPhase) % colorCount
            let toIndex = (fromIndex + 1) % colorCount
            let t = scaledPhase - Double(Int(scaledPhase))

            // Smooth sinusoidal interpolation for organic feel
            let smoothT = (1.0 - cos(t * .pi)) / 2.0

            let color = palette.interpolated(from: fromIndex, to: toIndex, t: smoothT)
            let intensity = context.parameters.intensity

            result[fixture.id] = [
                .red: color.red * intensity,
                .green: color.green * intensity,
                .blue: color.blue * intensity,
                .white: color.white * intensity,
            ]
        }

        return result
    }
}
